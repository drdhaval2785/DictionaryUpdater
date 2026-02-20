import 'package:isar/isar.dart';

part 'dictionary_models.g.dart';

@collection
class DictionaryMetadata {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String name;

  late String remoteUrl;

  late String localPath;

  late DateTime lastUpdated;

  DateTime? remoteLastModified;

  bool isDownloaded = false;

  String? version;
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
