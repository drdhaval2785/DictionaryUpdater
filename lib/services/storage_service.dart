import 'dart:io';
import 'package:flutter/foundation.dart';
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

  /// Returns true if a custom storage path has been set.
  bool get hasCustomPath => _prefs.containsKey(_storagePathKey);

  /// Returns the active dictionary storage directory, creating it if needed.
  Future<Directory> getStorageDirectory({String? sourceName}) async {
    final String? custom = _prefs.getString(_storagePathKey);
    if (custom != null && custom.isNotEmpty) {
      final dir = Directory(custom);
      if (await dir.exists()) {
        if (sourceName != null && sourceName.isNotEmpty) {
          final subDir = Directory(p.join(dir.path, sanitizeFolderName(sourceName)));
          if (!await subDir.exists()) {
            await subDir.create(recursive: true);
          }
          return subDir;
        }
        return dir;
      }
      // Custom path no longer valid — fall through to default
    }
    return getDefaultStorageDirectory(sourceName: sourceName);
  }

  /// Sets a custom storage path (persisted across restarts).
  Future<void> setCustomStoragePath(String path) =>
      _prefs.setString(_storagePathKey, path);

  /// Resets to the platform default.
  Future<void> resetToDefault() => _prefs.remove(_storagePathKey);

  /// Platform-safe default:
  /// - Mobile (Android/iOS): getApplicationDocumentsDirectory
  /// - Desktop (macOS, Windows, Linux): ~/Downloads/StarDictData
  Future<Directory> getDefaultStorageDirectory({String? sourceName}) async {
    final base = await getApplicationSupportDirectory();
    
    final basePath = p.join(base.path, _folderName);
    return _resolveFinalPath(basePath, sourceName);
  }

  Future<Directory> _resolveFinalPath(String basePath, String? sourceName) async {
    final String fullPath = (sourceName != null && sourceName.isNotEmpty)
        ? p.join(basePath, sanitizeFolderName(sourceName))
        : basePath;
        
    final dir = Directory(fullPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Sanitizes a file name to prevent path traversal and invalid characters.
  /// Preserves multiple underscores.
  String sanitizeFileName(String name) => name
      .replaceAll(' - ', '_')
      .replaceAll(RegExp(r'[<>:"/\\|?* ]'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  /// Sanitizes a folder name, collapsing multiple underscores into one.
  String sanitizeFolderName(String name) =>
      sanitizeFileName(name).replaceAll(RegExp(r'_{2,}'), '_');

  /// Checks if a dictionary file exists locally.
  Future<bool> dictionaryExists(String fileName, {String? sourceName}) async {
    final base = await getStorageDirectory(sourceName: sourceName);
    return File(p.join(base.path, sanitizeFileName(fileName))).exists();
  }

  /// Extracts the base part of an Indic-dict filename (part before the first '__').
  String? extractBaseName(String fileName) {
    if (fileName.contains('__')) {
      return fileName.split('__').first;
    }
    return null;
  }

  /// Looks for an existing file that shares the same base name but has a different
  /// full filename (likely an older timestamped version).
  Future<File?> findExistingVersion(String newFileName, {String? sourceName}) async {
    final baseDir = await getStorageDirectory(sourceName: sourceName);
    if (!await baseDir.exists()) return null;

    final targetBase = extractBaseName(newFileName);
    if (targetBase == null) return null; // Not an Indic-dict timestamped file

    try {
      final List<FileSystemEntity> entities = await baseDir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final existingName = p.basename(entity.path);
          if (existingName != newFileName && extractBaseName(existingName) == targetBase) {
            return entity;
          }
        }
      }
    } catch (e) {
      debugPrint('Error listing storage directory: $e');
    }
    return null;
  }
}
