import 'package:isar/isar.dart';
import '../models/dictionary_models.dart';

/// Registry for managing known and user-added dictionary sources.
class DictionaryRegistry {
  final Isar _isar;

  DictionaryRegistry(this._isar);

  /// Default GitHub source for dictionaries.
  static const String defaultSource = 'https://github.com/indic-dict/stardict-sanskrit/blob/gh-pages/sa-head/en-entries/tars/tars.MD';

  /// Removes any existing default (non-user-added) sources.
  Future<void> initializeDefaults() async {
    final existingDefault = await _isar.dictionarySources
        .filter()
        .isUserAddedEqualTo(false)
        .findAll();

    if (existingDefault.isNotEmpty) {
      await _isar.writeTxn(() async {
        await _isar.dictionarySources.deleteAll(existingDefault.map((s) => s.id).toList());
      });
    }
  }

  /// Returns all enabled sources.
  Future<List<DictionarySource>> getEnabledSources() async {
    return _isar.dictionarySources.filter().isEnabledEqualTo(true).findAll();
  }

  /// Adds a new user source, merging URLs if a source with the same label already exists.
  Future<DictionarySource> addUserSource(String url, String label) async {
    final existing = await _isar.dictionarySources.filter().labelEqualTo(label).findFirst();

    if (existing != null) {
      // If both are data: URIs, merge the newline-separated content
      if (existing.url.startsWith('data:') && url.startsWith('data:')) {
        final existingRaw = Uri.decodeComponent(existing.url.split(',').last);
        final newRaw = Uri.decodeComponent(url.split(',').last);

        final existingUrls = existingRaw.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
        final newUrls = newRaw.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();

        final mergedUrls = existingUrls.union(newUrls).toList();
        final mergedRaw = mergedUrls.join('\n');
        final mergedUrl = 'data:text/plain;charset=utf-8,${Uri.encodeComponent(mergedRaw)}';

        existing.url = mergedUrl;
        await _isar.writeTxn(() async {
          await _isar.dictionarySources.put(existing);
        });
        return existing;
      }
      // If URLs are identical, just return existing
      if (existing.url == url) return existing;
    }

    final source = DictionarySource()
      ..url = url
      ..label = label
      ..isUserAdded = true
      ..isEnabled = true;

    await _isar.writeTxn(() async {
      await _isar.dictionarySources.put(source);
    });
    return source;
  }

  /// Removes a user source.
  Future<void> removeSource(int id) async {
    await _isar.writeTxn(() async {
      await _isar.dictionarySources.delete(id);
    });
  }

  /// Toggles a source's enabled status.
  Future<void> toggleSource(int id) async {
    final source = await _isar.dictionarySources.get(id);
    if (source != null) {
      source.isEnabled = !source.isEnabled;
      await _isar.writeTxn(() async {
        await _isar.dictionarySources.put(source);
      });
    }
  }
}
