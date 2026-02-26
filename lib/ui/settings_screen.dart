import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _pathController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentPath();
  }

  Future<void> _loadCurrentPath() async {
    final storageService = ref.read(storageServiceProvider);
    final dir = await storageService.getStorageDirectory();
    if (mounted) {
      setState(() {
        _pathController.text = dir.path;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _pickPath() async {
    final currentPath = _pathController.text.isEmpty ? null : _pathController.text;
    final result = await FilePicker.platform.getDirectoryPath(
      initialDirectory: currentPath,
    );
    if (result != null) {
      final storageService = ref.read(storageServiceProvider);
      await storageService.setCustomStoragePath(result);
      if (mounted) {
        setState(() {
          _pathController.text = result;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage path updated')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const Text(
          'Storage',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 16),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.primary.withAlpha(50)),
          ),
          tileColor: theme.colorScheme.primaryContainer.withAlpha(30),
          leading: Icon(Icons.folder_open, color: theme.colorScheme.primary),
          title: const Text('Select the Download Folder'),
          subtitle: Text(
            _pathController.text.isEmpty
                ? 'No folder selected'
                : _pathController.text,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickPath,
        ),
        const SizedBox(height: 12),
        if (_pathController.text.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '⚠️ Please select a folder to enable dictionary downloads.',
              style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }
}
