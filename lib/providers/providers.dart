import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/storage_service.dart';
import '../services/dictionary_client.dart';
import '../services/dictionary_registry.dart';
import '../models/dictionary_models.dart';

/// Provider for SharedPreferences.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(); // Initialized in main
});

/// Provider for Isar database instance.
final isarProvider = Provider<Isar>((ref) {
  throw UnimplementedError(); // Initialized in main
});

/// Provider for StorageService.
final storageServiceProvider = Provider<StorageService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return StorageService(prefs);
});

/// Provider for Dio instance.
final dioProvider = Provider<Dio>((ref) {
  return Dio();
});

/// Provider for DictionaryClient.
final dictionaryClientProvider = Provider<DictionaryClient>((ref) {
  final dio = ref.watch(dioProvider);
  final storage = ref.watch(storageServiceProvider);
  return DictionaryClient(dio, storage);
});

/// Provider for DictionaryRegistry.
final dictionaryRegistryProvider = Provider<DictionaryRegistry>((ref) {
  final isar = ref.watch(isarProvider);
  return DictionaryRegistry(isar);
});

/// Async notifier for the list of dictionary sources.
final sourcesProvider = AsyncNotifierProvider<SourcesNotifier, List<DictionarySource>>(() {
  return SourcesNotifier();
});

class SourcesNotifier extends AsyncNotifier<List<DictionarySource>> {
  @override
  Future<List<DictionarySource>> build() {
    final registry = ref.watch(dictionaryRegistryProvider);
    return registry.getEnabledSources();
  }

  Future<DictionarySource> addSource(String url, String label) async {
    final registry = ref.read(dictionaryRegistryProvider);
    final source = await registry.addUserSource(url, label);
    ref.invalidateSelf();
    return source;
  }

  Future<void> removeSource(int id) async {
    final registry = ref.watch(dictionaryRegistryProvider);
    await registry.removeSource(id);
    ref.invalidateSelf();
  }
}
