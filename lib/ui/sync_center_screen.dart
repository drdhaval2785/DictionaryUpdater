import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/providers.dart';
import '../models/dictionary_models.dart';
import 'source_expansion_panel.dart';
import 'indic_dict_browser.dart';

class SyncCenterScreen extends ConsumerWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(sourcesProvider);

    // Collect total selected across all sources for the global FAB
    final allSources = sourcesAsync.valueOrNull ?? [];
    int totalSelected = 0;
    for (final source in allSources) {
      final items =
          ref.watch(sourceItemsProvider(source)).valueOrNull ?? [];
      totalSelected += items.where((i) => i.isSelected).length;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stardict Dictionary Updater'),
        toolbarHeight: 72,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Add Dictionary'),
              onPressed: () => _showAddSourceDialog(context, ref),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Check for Updates'),
                  onPressed: () {
                    ref.invalidate(sourcesProvider);
                    for (final s in allSources) {
                      ref.invalidate(sourceItemsProvider(s));
                    }
                    ref.read(lastCheckedAllProvider.notifier).updateTimestamp();
                  },
                ),
                Consumer(
                  builder: (context, ref, child) {
                    final lastChecked = ref.watch(lastCheckedAllProvider);
                    if (lastChecked == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 2, right: 4),
                      child: Text(
                        'Last checked for updates upstream on ${_fmtDt(lastChecked)}',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.grey,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: sourcesAsync.when(
        data: (sources) => sources.isEmpty
            ? _buildEmptyState(context, ref)
            : ListView.builder(
                itemCount: sources.length,
                padding: const EdgeInsets.only(bottom: 80),
                itemBuilder: (_, i) =>
                    SourceExpansionPanel(source: sources[i]),
              ),
        loading: () => _buildShimmer(),
        error: (err, _) => _buildError(err.toString()),
      ),
      // Global Download FAB — shows total selected across ALL sources
      floatingActionButton: totalSelected > 0
          ? FloatingActionButton.extended(
              heroTag: 'global_download',
              icon: const Icon(Icons.download_rounded),
              label: Text('Download $totalSelected from all sources'),
              onPressed: () => _downloadAll(context, ref, allSources),
            )
          : null,
    );
  }

  // ─── Global download ────────────────────────────────────────────────────────

  Future<void> _downloadAll(
      BuildContext context, WidgetRef ref, List<DictionarySource> sources) async {
    for (final DictionarySource source in sources) {
      final notifier = ref.read(sourceItemsProvider(source).notifier);
      final hasSelected =
          (ref.read(sourceItemsProvider(source)).valueOrNull ?? [])
              .any((i) => i.isSelected);
      if (hasSelected) {
        await notifier.downloadSelected();
      }
    }
  }

  String _fmtDt(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
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
            onPressed: () => _showAddSourceDialog(context, ref),
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

  // ─── Add Source Dialog ────────────────────────────────────────────────────

  void _showAddSourceDialog(BuildContext context, WidgetRef ref) {
    final fileLabelCtrl = TextEditingController();
    final fileCtrl = TextEditingController();
    final pasteLabelCtrl = TextEditingController();
    final pasteCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 3,
        child: AlertDialog(
          title: const Text('Add Dictionary'),
          content: SizedBox(
            width: double.maxFinite,
            height: 380,
            child: Column(
              children: [
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(icon: Icon(Icons.download_rounded), text: 'Download Indic-dicts'),
                    Tab(icon: Icon(Icons.file_open), text: 'Import Local File'),
                    Tab(icon: Icon(Icons.link), text: 'Download from Web'),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Tab 0: Indic-dicts launcher
                      _IndicDictsTab(onNavigate: () {
                        Navigator.pop(ctx);
                        Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => IndicDictBrowserScreen(ref: ref),
                          ),
                        );
                      }),
                      _FileTab(
                          labelCtrl: fileLabelCtrl, pathCtrl: fileCtrl),
                      _PasteTab(
                          labelCtrl: pasteLabelCtrl, pasteCtrl: pasteCtrl),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            Builder(builder: (tabCtx) {
              return ElevatedButton(
                onPressed: () async {
                  final tab = DefaultTabController.of(tabCtx).index;

                  // Tab 0 (Indic-dicts) handles its own navigation – no inline Add
                  if (tab == 0) return;

                  String label;
                  String url;

                  if (tab == 1) {
                    label = fileLabelCtrl.text.trim();
                    url = fileCtrl.text.trim();
                  } else {
                    label = pasteLabelCtrl.text.trim();
                    final raw = pasteCtrl.text.trim();
                    url = raw.isNotEmpty
                        ? 'data:text/plain;charset=utf-8,${Uri.encodeComponent(raw)}'
                        : '';
                  }

                  if (label.isEmpty || url.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Please fill in Source Name and content.')));
                    return;
                  }

                  await ref
                      .read(sourcesProvider.notifier)
                      .addSource(url, label);

                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Add'),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─── Tab sub-widgets ──────────────────────────────────────────────────────────

/// Tab 0: A simple launcher card for the Indic-dicts full-screen browser.
class _IndicDictsTab extends StatelessWidget {
  const _IndicDictsTab({required this.onNavigate});
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.language, size: 56, color: Colors.indigo),
          const SizedBox(height: 16),
          const Text(
            'Browse the Indic-dict repository',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select from hundreds of scholarly dictionaries',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onNavigate,
            icon: const Icon(Icons.search),
            label: const Text('Open Browser'),
          ),
        ],
      ),
    );
  }
}

class _FileTab extends StatelessWidget {
  const _FileTab({required this.labelCtrl, required this.pathCtrl});
  final TextEditingController labelCtrl;
  final TextEditingController pathCtrl;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(children: [
        TextField(
            controller: labelCtrl,
            decoration: const InputDecoration(labelText: 'Source Name')),
        const SizedBox(height: 8),
        TextField(
            controller: pathCtrl,
            enabled: false,
            decoration: const InputDecoration(labelText: 'File Path (auto-filled)')),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () async {
            final FilePickerResult? result =
                await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['md', 'MD', 'txt'],
            );
            if (result != null && result.files.single.path != null) {
              final file = File(result.files.single.path!);
              pathCtrl.text = file.uri.toString();
              if (labelCtrl.text.isEmpty) {
                labelCtrl.text = result.files.single.name;
              }
            }
          },
          icon: const Icon(Icons.file_open),
          label: const Text('Select Local File'),
        ),
      ]),
    );
  }
}

class _PasteTab extends StatelessWidget {
  const _PasteTab({required this.labelCtrl, required this.pasteCtrl});
  final TextEditingController labelCtrl;
  final TextEditingController pasteCtrl;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
          controller: labelCtrl,
          decoration: const InputDecoration(labelText: 'Source Name')),
      const SizedBox(height: 8),
      Expanded(
        child: TextField(
          controller: pasteCtrl,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(
            labelText: 'Paste links here',
            hintText:
                'https://example.com/dict.tar.gz\n[Dict](https://example.com/dict2.zip)',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    ]);
  }
}
