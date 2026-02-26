import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/dictionary_models.dart';
import 'providers/providers.dart';
import 'services/dictionary_registry.dart';
import 'services/storage_service.dart';
import 'ui/main_layout.dart';
import 'ui/setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final storageService = StorageService(prefs);
  
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [DictionaryMetadataSchema, DictionarySourceSchema],
    directory: dir.path,
  );

  // Initialize defaults
  final registry = DictionaryRegistry(isar);
  await registry.initializeDefaults();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        isarProvider.overrideWithValue(isar),
      ],
      child: StarDictManagerApp(isFirstLaunch: !storageService.hasCustomPath),
    ),
  );
}

class StarDictManagerApp extends StatelessWidget {
  final bool isFirstLaunch;
  const StarDictManagerApp({super.key, required this.isFirstLaunch});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stardict Dictionary Updater',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      home: isFirstLaunch ? const SetupScreen() : const MainLayout(),
    );
  }
}
