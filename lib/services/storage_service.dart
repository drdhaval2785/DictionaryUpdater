import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Service responsible for managing storage paths and file operations.
/// All data is stored in the user-visible 'DictionaryData' folder.
class StorageService {
  static const String _folderName = 'DictionaryData';

  final Directory? _baseDirOverride;

  StorageService({Directory? baseDirOverride})
    : _baseDirOverride = baseDirOverride;

  /// Returns the active dictionary storage directory, creating it if needed.
  Future<Directory> getStorageDirectory({String? sourceName}) async {
    final Directory? base;
    if (_baseDirOverride != null) {
      base = _baseDirOverride;
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      base = await getDownloadsDirectory();
    } else if (Platform.isAndroid) {
      base = await getExternalStorageDirectory();
    } else {
      // iOS and fallbacks
      base = await getApplicationDocumentsDirectory();
    }

    if (base == null) {
      // Fallback if platform-specific dir fails
      final fallback = await getApplicationSupportDirectory();
      final basePath = p.join(fallback.path, _folderName);
      return _resolveFinalPath(basePath, sourceName);
    }

    final basePath = p.join(base.path, _folderName);
    return _resolveFinalPath(basePath, sourceName);
  }

  /// Returns a user-friendly string describing the storage location.
  Future<String> getStoragePathDisplay() async {
    if (_baseDirOverride != null) {
      return p.join(_baseDirOverride.path, _folderName);
    }

    if (Platform.isIOS) {
      return 'Files App -> On My iPhone -> Dictionary Updater -> $_folderName';
    }

    if (Platform.isMacOS) {
      return 'Downloads Folder -> DictionaryData';
    }

    if (Platform.isWindows || Platform.isLinux) {
      final Directory? base = await getDownloadsDirectory();
      if (base == null) {
        final fallback = await getApplicationSupportDirectory();
        return p.join(fallback.path, _folderName);
      }
      return p.join(base.path, _folderName);
    }

    if (Platform.isAndroid) {
      final base = await getExternalStorageDirectory();
      if (base == null) {
        final fallback = await getApplicationSupportDirectory();
        return p.join(fallback.path, _folderName);
      }
      return p.join(base.path, _folderName);
    }

    try {
      final base = await getApplicationDocumentsDirectory();
      return p.join(base.path, _folderName);
    } catch (e) {
      final fallback = await getApplicationSupportDirectory();
      return p.join(fallback.path, _folderName);
    }
  }

  Future<Directory> _resolveFinalPath(
    String basePath,
    String? sourceName,
  ) async {
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
  /// First checks the source-specific subfolder, then falls back to the root folder.
  Future<bool> dictionaryExists(String fileName, {String? sourceName}) async {
    final sanitizedName = sanitizeFileName(fileName);

    // Check source-specific subfolder
    if (sourceName != null && sourceName.isNotEmpty) {
      final sourceBase = await getStorageDirectory(sourceName: sourceName);
      if (await File(p.join(sourceBase.path, sanitizedName)).exists())
        return true;
    }

    // Check root folder
    final rootBase = await getStorageDirectory();
    return File(p.join(rootBase.path, sanitizedName)).exists();
  }

  /// Extracts the base part of an Indic-dict filename (part before the first '__').
  String? extractBaseName(String fileName) {
    if (fileName.contains('__')) {
      return fileName.split('__').first;
    }
    return null;
  }

  /// Extracts the timestamp from an Indic-dict filename.
  /// Pattern: __2022-01-22_15-15-47Z__
  /// Returns a DateTime in UTC.
  DateTime? extractTimestamp(String fileName) {
    final regExp = RegExp(r'__(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})Z__');
    final match = regExp.firstMatch(fileName);
    if (match != null) {
      final date = match.group(1);
      final h = match.group(2);
      final m = match.group(3);
      final s = match.group(4);
      // Construct ISO 8601 string: 2022-01-22T15:15:47Z
      final isoString = '${date}T$h:$m:${s}Z';
      try {
        return DateTime.parse(isoString);
      } catch (e) {
        debugPrint('Error parsing extracted timestamp $isoString: $e');
      }
    }
    return null;
  }

  /// Looks for an existing file that shares the same base name but has a different
  /// full filename (likely an older timestamped version).
  /// Searches both the source-specific subfolder and the root folder.
  Future<File?> findExistingVersion(
    String newFileName, {
    String? sourceName,
  }) async {
    final sanitizedNewName = sanitizeFileName(newFileName);
    final targetBase = extractBaseName(sanitizedNewName);
    if (targetBase == null) return null;

    // 1. Check source-specific subfolder
    if (sourceName != null && sourceName.isNotEmpty) {
      final sourceBase = await getStorageDirectory(sourceName: sourceName);
      final found = await _findInDirectory(
        sourceBase,
        sanitizedNewName,
        targetBase,
      );
      if (found != null) return found;
    }

    // 2. Check root folder
    final rootBase = await getStorageDirectory();
    return _findInDirectory(rootBase, sanitizedNewName, targetBase);
  }

  Future<File?> _findInDirectory(
    Directory dir,
    String newFileName,
    String targetBase,
  ) async {
    if (!await dir.exists()) return null;
    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final existingName = p.basename(entity.path);
          // Match if it's a different filename but has the same base (indic-dict pattern)
          if (existingName != newFileName &&
              extractBaseName(existingName) == targetBase) {
            return entity;
          }
        }
      }
    } catch (e) {
      debugPrint('Error listing directory ${dir.path}: $e');
    }
    return null;
  }
}
