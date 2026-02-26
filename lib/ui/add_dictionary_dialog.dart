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
    builder: (ctx) => AlertDialog(
      title: const Text('Add Dictionary'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Option 1: Indic-dicts (Direct Navigation)
              _CategoryCard(
                icon: Icons.language_rounded,
                title: 'Indic-dict Repository',
                subtitle: 'Browse 100s of scholarly dictionaries',
                color: Colors.indigo,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => IndicDictBrowserScreen(ref: ref),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              // Option 2: Local File (Expandable)
              _ExpandableCategoryCard(
                icon: Icons.file_open_rounded,
                title: 'Import Local File',
                subtitle: 'Select .md, .txt or .zip from device',
                color: Colors.teal,
                child: Column(
                  children: [
                    _FileTab(labelCtrl: fileLabelCtrl, pathCtrl: fileCtrl),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _handleAdd(ref, context, ctx, fileLabelCtrl, fileCtrl, isLocal: true),
                        icon: const Icon(Icons.add_task),
                        label: const Text('Import File'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Option 3: Web (Expandable)
              _ExpandableCategoryCard(
                icon: Icons.link_rounded,
                title: 'Download from Web',
                subtitle: 'Paste links or formatted markdown',
                color: Colors.orange,
                child: Column(
                  children: [
                    _PasteTab(labelCtrl: pasteLabelCtrl, pasteCtrl: pasteCtrl),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                        onPressed: () => _handleAdd(ref, context, ctx, pasteLabelCtrl, pasteCtrl, isLocal: false),
                        icon: const Icon(Icons.cloud_download),
                        label: const Text('Add Links'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withAlpha(50)),
      ),
      color: color.withAlpha(15),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      ),
    );
  }
}

class _ExpandableCategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Widget child;

  const _ExpandableCategoryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withAlpha(50)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        backgroundColor: color.withAlpha(10),
        collapsedBackgroundColor: color.withAlpha(10),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        shape: const Border(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }
}

Future<void> _handleAdd(
    WidgetRef ref,
    BuildContext context,
    BuildContext dialogCtx,
    TextEditingController labelCtrl,
    TextEditingController contentCtrl,
    {required bool isLocal}) async {
  final label = labelCtrl.text.trim();
  final raw = contentCtrl.text.trim();
  
  if (label.isEmpty || raw.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in Source Name and content.')));
    return;
  }

  String url = raw;
  if (!isLocal) {
    url = 'data:text/plain;charset=utf-8,${Uri.encodeComponent(raw)}';
  }

  await ref.read(sourcesProvider.notifier).addSource(url, label);
  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
}


// ─── Tab sub-widgets ──────────────────────────────────────────────────────────


class _FileTab extends StatelessWidget {
  const _FileTab({required this.labelCtrl, required this.pathCtrl});
  final TextEditingController labelCtrl;
  final TextEditingController pathCtrl;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
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
    ]);
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
      TextField(
        controller: pasteCtrl,
        minLines: 5,
        maxLines: 10,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          labelText: 'Paste links here',
          hintText:
              'https://example.com/dict.tar.gz\n[Dict](https://example.com/dict2.zip)',
          border: OutlineInputBorder(),
        ),
      ),
    ]);
  }
}
