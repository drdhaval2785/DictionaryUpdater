import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/providers.dart';
import '../models/dictionary_models.dart';
import 'source_expansion_panel.dart';
import 'add_dictionary_dialog.dart';

class SyncCenterScreen extends ConsumerWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(sourcesProvider);

    // Collect total selected across all sources for the global FAB
    final allSources = sourcesAsync.valueOrNull ?? [];
    int totalSelected = 0;
    double totalSizeMb = 0;
    for (final source in allSources) {
      final items =
          ref.watch(sourceItemsProvider(source)).valueOrNull ?? [];
      final selectedItems = items.where((i) => i.isSelected).toList();
      totalSelected += selectedItems.length;
      for (final item in selectedItems) {
        totalSizeMb += item.sizeMb ?? 0;
      }
    }

    return Stack(
      children: [
        sourcesAsync.when(
          data: (sources) => sources.isEmpty
              ? _buildEmptyState(context, ref)
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
        if (totalSelected > 0)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'global_download',
              icon: const Icon(Icons.download_rounded),
              label: Text(totalSizeMb > 0
                  ? 'Download $totalSelected (${totalSizeMb.toStringAsFixed(1)} MB)'
                  : 'Download $totalSelected'),
              onPressed: () => _downloadAll(context, ref, allSources, totalSizeMb),
            ),
          ),
      ],
    );
  }

  // ─── Global download ────────────────────────────────────────────────────────

  Future<void> _downloadAll(BuildContext context, WidgetRef ref,
      List<DictionarySource> sources, double totalSizeMb) async {
    if (totalSizeMb > 50) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Large Download'),
          content: Text(
              'You are about to download ${totalSizeMb.toStringAsFixed(1)} MB of data. Are you sure?'),
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

    for (final DictionarySource source in sources) {
      final notifier = ref.read(sourceItemsProvider(source).notifier);
      final hasSelected =
          (ref.read(sourceItemsProvider(source)).valueOrNull ?? [])
              .any((i) => i.isSelected);
      if (hasSelected) {
        if (!context.mounted) break;
        await notifier.downloadSelected(context);
      }
    }
  }

  // ─── Empty state ─────────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.library_books_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No sources yet. Add one to get started.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
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
