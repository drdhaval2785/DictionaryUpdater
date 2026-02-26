import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/providers.dart';
import 'main_layout.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  bool _isPicking = false;

  Future<void> _pickDirectory() async {
    setState(() => _isPicking = true);
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null) {
        final storageService = ref.read(storageServiceProvider);
        await storageService.setCustomStoragePath(result);
        if (mounted) {
          await Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(builder: (context) => const MainLayout()),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_shared_outlined, size: 100, color: Colors.blue),
              const SizedBox(height: 32),
              Text(
                'Welcome to Dictionary Updater',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Please select a folder where you would like to store your dictionary data. This ensures the app stays within its sandbox while giving you control over your files.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 48),
              if (_isPicking)
                const CircularProgressIndicator()
              else
                ElevatedButton.icon(
                  onPressed: _pickDirectory,
                  icon: const Icon(Icons.create_new_folder),
                  label: const Text('Select Storage Folder'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Warning: Dictionaries will not be downloaded until a storage folder is selected in Settings.'),
                      duration: Duration(seconds: 5),
                    ),
                  );
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute<void>(builder: (context) => const MainLayout()),
                  );
                },
                child: const Text('Skip for now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
