import 'package:isar/isar.dart';

part 'dictionary_models.g.dart';

@collection
class DictionaryMetadata {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String name;

  String? sourceName; // Link to the 'label' from DictionarySource

  late String remoteUrl;

  late String localPath;

  late DateTime lastUpdated;

  DateTime? remoteLastModified;

  /// When the machine last performed a HEAD request to check for upstream changes.
  DateTime? lastChecked;

  bool isDownloaded = false;

  String? version;

  double? sizeMb;
}

@collection
class DictionarySource {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String url;

  late String label;

  bool isUserAdded = false;

  bool isEnabled = true;
}
