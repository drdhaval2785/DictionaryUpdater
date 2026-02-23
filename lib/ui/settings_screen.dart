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
    setState(() {
      _pathController.text = dir.path;
      _isLoading = false;
    });
  }

  Future<void> _savePath() async {
    final newPath = _pathController.text.trim();
    if (newPath.isEmpty) return;

    final storageService = ref.read(storageServiceProvider);
    await storageService.setCustomStoragePath(newPath);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage path updated manually')),
      );
    }
  }

  Future<void> _pickPath() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      _pathController.text = result;
      await _savePath();
    }
  }

  Future<void> _resetPath() async {
    final storageService = ref.read(storageServiceProvider);
    await storageService.resetToDefault();
    await _loadCurrentPath();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage path reset to default')),
      );
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Storage',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _pathController,
                  decoration: const InputDecoration(
                    labelText: 'Storage Path',
                    border: OutlineInputBorder(),
                    helperText: 'Where dictionary files will be downloaded',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.folder_open),
                    tooltip: 'Browse',
                    onPressed: _pickPath,
                  ),
                  const SizedBox(height: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.save),
                    tooltip: 'Save Manual Edit',
                    onPressed: _savePath,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.withAlpha(50)),
            ),
            leading: const Icon(Icons.restore),
            title: const Text('Reset to Default Path'),
            onTap: _resetPath,
          ),
        ],
      );
  }
}
