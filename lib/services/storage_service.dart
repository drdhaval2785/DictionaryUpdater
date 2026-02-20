import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service responsible for managing storage paths and file operations.
///
/// Default path priority (guaranteed to always exist and be writable):
///  1. User-defined path from SharedPreferences
///  2. {ApplicationSupportDir}/StarDictData  (safe on ALL platforms & sandboxes)
class StorageService {
  static const String _storagePathKey = 'custom_storage_path';
  static const String _folderName = 'StarDictData';

  final SharedPreferences _prefs;
  StorageService(this._prefs);

  /// Returns the active dictionary storage directory, creating it if needed.
  Future<Directory> getStorageDirectory() async {
    final String? custom = _prefs.getString(_storagePathKey);
    if (custom != null && custom.isNotEmpty) {
      final dir = Directory(custom);
      if (await dir.exists()) return dir;
      // Custom path no longer valid — fall through to default
    }
    return getDefaultStorageDirectory();
  }

  /// Sets a custom storage path (persisted across restarts).
  Future<void> setCustomStoragePath(String path) =>
      _prefs.setString(_storagePathKey, path);

  /// Resets to the platform default.
  Future<void> resetToDefault() => _prefs.remove(_storagePathKey);

  /// Platform-safe default:
  /// - Mobile (Android/iOS): getApplicationDocumentsDirectory
  /// - Desktop (macOS, Windows, Linux): ~/Downloads/StarDictData
  Future<Directory> getDefaultStorageDirectory() async {
    Directory base;
    if (Platform.isAndroid || Platform.isIOS) {
      base = await getApplicationDocumentsDirectory();
    } else {
      // For desktop, bypass sandbox abstractions to get the REAL Downloads folder.
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) {
        base = Directory(p.join(home, 'Downloads'));
      } else {
        base = await getApplicationSupportDirectory();
      }
    }
    final dir = Directory(p.join(base.path, _folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Sanitizes a file name to prevent path traversal and invalid characters.
  String sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

  /// Checks if a dictionary file exists locally.
  Future<bool> dictionaryExists(String fileName) async {
    final base = await getStorageDirectory();
    return File(p.join(base.path, sanitizeFileName(fileName))).exists();
  }
}
