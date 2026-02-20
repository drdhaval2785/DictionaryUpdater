import 'package:isar/isar.dart';
import '../models/dictionary_models.dart';

/// Registry for managing known and user-added dictionary sources.
class DictionaryRegistry {
  final Isar _isar;

  DictionaryRegistry(this._isar);

  /// Default GitHub source for dictionaries.
  static const String defaultSource = 'https://github.com/indic-dict/stardict-sanskrit/blob/gh-pages/sa-head/en-entries/tars/tars.MD';

  /// Initializes the registry with default sources if empty, or updates stale ones.
  Future<void> initializeDefaults() async {
    final existing = await _isar.dictionarySources
        .filter()
        .isUserAddedEqualTo(false)
        .findAll();

    // Remove old default sources that don't match the current default URL
    final stale = existing.where((s) => s.url != defaultSource).toList();
    if (stale.isNotEmpty) {
      await _isar.writeTxn(() async {
        await _isar.dictionarySources.deleteAll(stale.map((s) => s.id).toList());
      });
    }

    final currentDefault = await _isar.dictionarySources
        .filter()
        .urlEqualTo(defaultSource)
        .findFirst();

    if (currentDefault == null) {
      final defaultSrc = DictionarySource()
        ..url = defaultSource
        ..label = 'Indic-Dict Sanskrit (Default)'
        ..isUserAdded = false
        ..isEnabled = true;

      await _isar.writeTxn(() async {
        await _isar.dictionarySources.put(defaultSrc);
      });
    }
  }

  /// Returns all enabled sources.
  Future<List<DictionarySource>> getEnabledSources() async {
    return _isar.dictionarySources.filter().isEnabledEqualTo(true).findAll();
  }

  /// Adds a new user source.
  Future<DictionarySource> addUserSource(String url, String label) async {
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
