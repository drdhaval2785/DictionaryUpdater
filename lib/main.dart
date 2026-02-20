import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/dictionary_models.dart';
import 'providers/providers.dart';
import 'services/dictionary_registry.dart';
import 'ui/main_layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  
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
      child: const StarDictManagerApp(),
    ),
  );
}

class StarDictManagerApp extends StatelessWidget {
  const StarDictManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StarDict Manager',
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
      home: const MainLayout(),
    );
  }
}
