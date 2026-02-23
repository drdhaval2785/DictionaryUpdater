import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/providers.dart';
import 'indic_dict_browser.dart';

void showAddDictionaryDialog(BuildContext context, WidgetRef ref) {
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

// ─── Tab sub-widgets ──────────────────────────────────────────────────────────

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
