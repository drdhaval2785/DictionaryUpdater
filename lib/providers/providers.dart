import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/storage_service.dart';
import '../services/dictionary_client.dart';
import '../services/dictionary_registry.dart';
import '../models/dictionary_models.dart';

/// Provider for SharedPreferences.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(); // Initialized in main
});

/// Provider for PackageInfo.
final packageInfoProvider = Provider<PackageInfo>((ref) {
  throw UnimplementedError(); // Initialized in main
});

/// Provider for Isar database instance.
final isarProvider = Provider<Isar>((ref) {
  throw UnimplementedError(); // Initialized in main
});

/// Provider for StorageService.
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

/// Provider for Dio instance.
final dioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));
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

/// Provider for the global "Last checked for updates" timestamp.
final lastCheckedAllProvider =
    NotifierProvider<LastCheckedAllNotifier, DateTime?>(() {
  return LastCheckedAllNotifier();
});

/// Provider for accumulating resources that failed to update/download.
///
/// Various UI components listen to this provider and display a dialog when
/// the list becomes non‑empty.  Notifier callers append to the list, and
/// the dialog clears it by resetting to an empty list.
final failedResourcesProvider = StateProvider<List<String>>((ref) => []);

class LastCheckedAllNotifier extends Notifier<DateTime?> {
  static const _key = 'last_checked_all';

  @override
  DateTime? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = prefs.getString(_key);
    if (stored == null) return null;
    return DateTime.tryParse(stored);
  }

  Future<void> updateTimestamp() async {
    final now = DateTime.now();
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_key, now.toIso8601String());
    state = now;
  }
}

/// Provider to trigger a global refresh.
final refreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Provider for the Indic repository index markdown.
final repoIndexProvider = FutureProvider<String>((ref) async {
  final dio = ref.watch(dioProvider);
  const url = 'https://github.com/indic-dict/stardict-index/releases/download/current/dictionaryIndices.md';
  final resp = await dio.get<String>(url);
  return resp.data ?? '';
});
