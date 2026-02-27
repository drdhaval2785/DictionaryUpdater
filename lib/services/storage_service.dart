import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Service responsible for managing storage paths and file operations.
/// All data is stored in the user-visible 'DictionaryData' folder.
class StorageService {
  static const String _folderName = 'DictionaryData';

  final Directory? _baseDirOverride;

  StorageService({Directory? baseDirOverride}) : _baseDirOverride = baseDirOverride;

  /// Returns the active dictionary storage directory, creating it if needed.
  Future<Directory> getStorageDirectory({String? sourceName}) async {
    final Directory base = _baseDirOverride ?? await getApplicationDocumentsDirectory();
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
    if (targetBase == null) return null;

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
