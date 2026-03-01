import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/providers.dart';
import '../models/dictionary_models.dart';
import 'source_expansion_panel.dart';
import 'indic_dict_tab.dart';
import '../services/dictionary_client.dart';

class SyncCenterScreen extends ConsumerStatefulWidget {
  const SyncCenterScreen({super.key});

  @override
  ConsumerState<SyncCenterScreen> createState() => _SyncCenterScreenState();
}

class _SyncCenterScreenState extends ConsumerState<SyncCenterScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(text: 'Indic-dict'),
              Tab(text: 'Your lists'),
            ],
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            indicatorSize: TabBarIndicatorSize.tab,
          ),
          const Expanded(
            child: TabBarView(
              children: [
                IndicDictTab(),
                CustomizedSourcesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CustomizedSourcesTab extends ConsumerStatefulWidget {
  const CustomizedSourcesTab({super.key});

  @override
  ConsumerState<CustomizedSourcesTab> createState() => _CustomizedSourcesTabState();
}

class _CustomizedSourcesTabState extends ConsumerState<CustomizedSourcesTab> {
  final _labelCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _isAdding = false;
  int _batchTotal = 0;
  int _batchCurrent = 0;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _addSource() async {
    final label = _labelCtrl.text.trim();
    final raw = _contentCtrl.text.trim();
    if (label.isEmpty || raw.isEmpty) return;

    final url = 'data:text/plain;charset=utf-8,${Uri.encodeComponent(raw)}';
    await ref.read(sourcesProvider.notifier).addSource(url, label);
    
    _labelCtrl.clear();
    _contentCtrl.clear();
    setState(() => _isAdding = false);
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourcesProvider);
    final allSources = sourcesAsync.valueOrNull ?? [];

    int totalSelected = 0;
    double totalSizeMb = 0;
    bool isAnyDownloading = false;

    int totalAvailable = 0;
    int totalDownloaded = 0;
    int totalUpToDate = 0;
    int totalNewer = 0;

    for (final source in allSources) {
      final items = ref.watch(sourceItemsProvider(source)).valueOrNull ?? [];
      totalAvailable += items.length;
      totalUpToDate += items.where((i) => i.status == DictionaryStatus.upToDate).length;
      totalNewer += items.where((i) => i.status == DictionaryStatus.updateAvailable).length;

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
    totalDownloaded = totalUpToDate + totalNewer;

    if (ref.watch(indicDownloadingProvider)) {
      isAnyDownloading = true;
    }

    return Stack(
      children: [
        Column(
          children: [
            // Inline Add Source Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                child: ExpansionTile(
                  key: ValueKey(_isAdding),
                  initiallyExpanded: _isAdding,
                  onExpansionChanged: (v) => setState(() => _isAdding = v),
                  title: const Text('Add Customized Source', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  leading: const Icon(Icons.add_link),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _labelCtrl,
                            decoration: const InputDecoration(labelText: 'Source Name', isDense: true),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _contentCtrl,
                            minLines: 2,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: 'Paste links or markdown here',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _addSource,
                              icon: const Icon(Icons.add),
                              label: const Text('Add to Lists'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Summary Stats Header
            if (totalAvailable > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$totalAvailable dictionaries available • $totalDownloaded downloaded',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalUpToDate up to date • $totalNewer have newer version',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: sourcesAsync.when(
                data: (sources) => sources.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: sources.length,
                        padding: const EdgeInsets.only(bottom: 80),
                        itemBuilder: (_, i) => SourceExpansionPanel(source: sources[i]),
                      ),
                loading: () => _buildShimmer(),
                error: (err, _) => Center(child: Text(err.toString())),
              ),
            ),
          ],
        ),
        if (totalSelected > 0 || isAnyDownloading)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  )
                ],
              ),
              child: SafeArea(
                child: isAnyDownloading
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
                                      value: _batchTotal > 0 ? _batchCurrent / _batchTotal : 0,
                                      minHeight: 8,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '$_batchCurrent/$_batchTotal downloaded',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              for (final source in allSources) {
                                ref.read(sourceItemsProvider(source).notifier).cancelDownloads();
                              }
                              ref.read(indicCancelTriggerProvider.notifier).state++;
                            },
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop All'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.download_rounded),
                        label: Text('Download $totalSelected (${totalSizeMb.toStringAsFixed(1)} MB)'),
                        onPressed: () => _downloadAll(allSources, totalSizeMb),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _downloadAll(List<DictionarySource> sources, double totalSizeMb) async {
    final storageService = ref.read(storageServiceProvider);
    final storagePath = await storageService.getStoragePathDisplay();

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Download'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to download ${totalSizeMb.toStringAsFixed(1)} MB?'),
            const SizedBox(height: 16),
            const Text('Storage Location:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(storagePath, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Download')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    int totalToDownload = 0;
    for (final source in sources) {
      final items = ref.read(sourceItemsProvider(source)).valueOrNull ?? [];
      totalToDownload += items.where((i) => i.isSelected).length;
    }

    setState(() {
      _batchTotal = totalToDownload;
      _batchCurrent = 0;
    });

    for (final source in sources) {
      if (!mounted) break;
      final notifier = ref.read(sourceItemsProvider(source).notifier);
      await notifier.downloadSelected(
        context,
        skipConfirmation: true,
        onDownloadComplete: () {
          if (mounted) {
            setState(() {
              _batchCurrent++;
            });
          }
        },
      );
    }
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('No customized lists yet.\nPaste links above to add your own.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13)),
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
        child: ListTile(
          leading: Container(width: 40, height: 40, color: Colors.white),
          title: Container(height: 16, color: Colors.white),
          subtitle: Container(width: 200, height: 12, color: Colors.white),
        ),
      ),
    );
  }
}

