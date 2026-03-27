import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_7zip/flutter_7zip.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Entry for checksum metadata tracking
class ChecksumEntry {
  final String baseName;
  final String md5;
  final DateTime? timestamp;
  final DateTime downloadedAt;

  ChecksumEntry({
    required this.baseName,
    required this.md5,
    this.timestamp,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() => {
    'baseName': baseName,
    'md5': md5,
    'timestamp': timestamp?.toIso8601String(),
    'downloadedAt': downloadedAt.toIso8601String(),
  };

  factory ChecksumEntry.fromJson(Map<String, dynamic> json) => ChecksumEntry(
    baseName: json['baseName'] as String,
    md5: json['md5'] as String,
    timestamp: json['timestamp'] != null
        ? DateTime.tryParse(json['timestamp'] as String)
        : null,
    downloadedAt: DateTime.parse(json['downloadedAt'] as String),
  );
}

/// Service responsible for managing storage paths and file operations.
/// All data is stored in the user-visible 'DictionaryData' folder.
class StorageService {
  static const String _folderName = 'DictionaryData';
  static const String _checksumFileName = 'checksums.json';

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

  /// Common dictionary file extensions that indicate decompressed files
  static const List<String> _dictExtensions = [
    '.dict.dz',
    '.dict',
    '.idx',
    '.wav',
    '.mp3',
    '.info',
    '.ifo',
    '.syn',
    '.abs',
    '.log',
  ];

  /// Returns the base name from a dictionary file (without extension)
  /// e.g., 'sa-IAST-kRdanta.dict.dz' -> 'sa-IAST-kRdanta'
  String? getBaseNameFromDictFile(String fileName) {
    for (final ext in _dictExtensions) {
      if (fileName.toLowerCase().endsWith(ext)) {
        return fileName.substring(0, fileName.length - ext.length);
      }
    }
    return null;
  }

  /// Checks if a dictionary file exists locally (decompressed form).
  /// Checks for common dictionary file extensions (.dict.dz, .idx, .wav, etc.)
  Future<bool> dictionaryExists(
    String archiveName, {
    String? sourceName,
  }) async {
    final baseName =
        extractBaseName(archiveName) ?? sanitizeFileName(archiveName);
    return await hasDecompressedFiles(baseName, sourceName: sourceName);
  }

  /// Checks if decompressed dictionary files exist for a given base name
  Future<bool> hasDecompressedFiles(
    String baseName, {
    String? sourceName,
  }) async {
    // Check source-specific subfolder
    if (sourceName != null && sourceName.isNotEmpty) {
      final sourceBase = await getStorageDirectory(sourceName: sourceName);
      if (await _hasAnyDictFile(sourceBase, baseName)) {
        return true;
      }
    }

    // Check root folder
    final rootBase = await getStorageDirectory();
    return await _hasAnyDictFile(rootBase, baseName);
  }

  Future<bool> _hasAnyDictFile(Directory dir, String baseName) async {
    if (!await dir.exists()) return false;
    try {
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final name = p.basename(entity.path).toLowerCase();
          if (name.startsWith(baseName.toLowerCase())) {
            // Check if it's a dictionary file extension
            for (final ext in _dictExtensions) {
              if (name.endsWith(ext)) {
                return true;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking directory ${dir.path}: $e');
    }
    return false;
  }

  /// Extracts the base part of an Indic-dict filename (part before the first '__').
  String? extractBaseName(String fileName) {
    // First check for the __timestamp__ pattern
    if (fileName.contains('__')) {
      return fileName.split('__').first;
    }
    // Also handle the older format: name_20240101_123456_1.2MB.tar.gz
    final oldFormat = RegExp(r'^(.+?)_\d{8}_\d{6}_');
    final match = oldFormat.firstMatch(fileName);
    if (match != null) {
      return match.group(1);
    }
    return null;
  }

  /// Extracts the timestamp from an Indic-dict filename.
  /// Pattern: __2022-01-22_15-15-47Z__
  /// Returns a DateTime in UTC.
  DateTime? extractTimestamp(String fileName) {
    // New format: __2022-01-22_15-15-47Z__
    var regExp = RegExp(r'__(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})Z__');
    var match = regExp.firstMatch(fileName);
    if (match != null) {
      final date = match.group(1);
      final h = match.group(2);
      final m = match.group(3);
      final s = match.group(4);
      final isoString = '${date}T$h:$m:${s}Z';
      try {
        return DateTime.parse(isoString);
      } catch (e) {
        debugPrint('Error parsing extracted timestamp $isoString: $e');
      }
    }

    // Old format: name_20240101_123456
    final oldFormat = RegExp(r'_(\d{8})_(\d{6})_');
    final oldMatch = oldFormat.firstMatch(fileName);
    if (oldMatch != null) {
      final date = oldMatch.group(1)!;
      final time = oldMatch.group(2)!;
      try {
        final year = int.parse(date.substring(0, 4));
        final month = int.parse(date.substring(4, 6));
        final day = int.parse(date.substring(6, 8));
        final hour = int.parse(time.substring(0, 2));
        final minute = int.parse(time.substring(2, 4));
        final second = int.parse(time.substring(4, 6));
        return DateTime.utc(year, month, day, hour, minute, second);
      } catch (e) {
        debugPrint('Error parsing old format timestamp: $e');
      }
    }

    return null;
  }

  /// Looks for existing decompressed files that share the same base name.
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
      final found = await _findDecompressedInDirectory(sourceBase, targetBase);
      if (found != null) return found;
    }

    // 2. Check root folder
    final rootBase = await getStorageDirectory();
    return await _findDecompressedInDirectory(rootBase, targetBase);
  }

  Future<File?> _findDecompressedInDirectory(
    Directory dir,
    String targetBase,
  ) async {
    if (!await dir.exists()) return null;
    try {
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final name = p.basename(entity.path);
          final base = getBaseNameFromDictFile(name);
          if (base == targetBase) {
            return entity;
          }
        }
      }
    } catch (e) {
      debugPrint('Error listing directory ${dir.path}: $e');
    }
    return null;
  }

  /// Returns compression type for a file (e.g., '.tar.gz', '.zip', '.7z')
  String? detectCompressionType(String filename) {
    final lower = filename.toLowerCase();
    const types = [
      '.tar.gz',
      '.tgz',
      '.tar.bz2',
      '.tbz2',
      '.tar.xz',
      '.txz',
      '.tar.lzma',
      '.tlz',
      '.tar.zst',
      '.tzst',
      '.zip',
      '.7z',
      '.rar',
      '.bz2',
      '.xz',
      '.lzma',
      '.zst',
      '.dz',
    ];
    for (final type in types) {
      if (lower.endsWith(type)) return type;
    }
    return null;
  }

  /// Computes MD5 checksum of a file
  Future<String> computeMD5(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }
    final bytes = await file.readAsBytes();
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// Returns the path to the global checksums.json file
  Future<File> _getChecksumFile() async {
    final storageDir = await getStorageDirectory();
    return File(p.join(storageDir.path, _checksumFileName));
  }

  /// Reads checksum metadata from global file
  Future<Map<String, ChecksumEntry>> readChecksumMetadata() async {
    try {
      final file = await _getChecksumFile();
      if (!await file.exists()) {
        return {};
      }
      final content = await file.readAsString();
      final Map<String, dynamic> json =
          jsonDecode(content) as Map<String, dynamic>;
      final result = <String, ChecksumEntry>{};
      for (final entry in json.entries) {
        result[entry.key] = ChecksumEntry.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
      return result;
    } catch (e) {
      debugPrint('Error reading checksum metadata: $e');
      return {};
    }
  }

  /// Updates checksum metadata for a dictionary
  Future<void> updateChecksumMetadata(
    String baseName,
    String md5,
    DateTime? timestamp,
  ) async {
    try {
      final metadata = await readChecksumMetadata();
      metadata[baseName] = ChecksumEntry(
        baseName: baseName,
        md5: md5,
        timestamp: timestamp,
        downloadedAt: DateTime.now(),
      );

      final file = await _getChecksumFile();
      final jsonMap = <String, dynamic>{};
      for (final entry in metadata.entries) {
        jsonMap[entry.key] = entry.value.toJson();
      }
      await file.writeAsString(jsonEncode(jsonMap));
    } catch (e) {
      debugPrint('Error updating checksum metadata: $e');
    }
  }

  /// Gets checksum entry for a specific base name
  Future<ChecksumEntry?> getChecksumEntry(String baseName) async {
    final metadata = await readChecksumMetadata();
    return metadata[baseName];
  }

  /// Decompresses archive into destination folder and optionally deletes original
  /// Handles: tar.gz, tgz, tar.bz2, tbz2, tar.xz, txz, zip, 7z, rar, bz2, xz, lzma, zst
  Future<void> decompressAndCleanup(
    String archivePath,
    String destFolder, {
    bool deleteArchive = true,
  }) async {
    final archiveFile = File(archivePath);
    if (!await archiveFile.exists()) {
      throw Exception('Archive file not found: $archivePath');
    }

    final compressionType = detectCompressionType(p.basename(archivePath));
    if (compressionType == null) {
      throw Exception('Unknown compression type: $archivePath');
    }

    final destDir = Directory(destFolder);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    try {
      final bytes = await archiveFile.readAsBytes();
      Archive? archive;

      if (compressionType == '.zip') {
        archive = ZipDecoder().decodeBytes(bytes);
      } else if (compressionType == '.tar.gz' || compressionType == '.tgz') {
        archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
      } else if (compressionType == '.tar.bz2' || compressionType == '.tbz2') {
        archive = TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes));
      } else if (compressionType == '.tar.xz' || compressionType == '.txz') {
        archive = TarDecoder().decodeBytes(XZDecoder().decodeBytes(bytes));
      } else if (compressionType == '.tar.zst' || compressionType == '.tzst') {
        debugPrint('zst format detected but not supported in this version');
        throw Exception('Zstandard (.tar.zst) format not supported');
      } else if (compressionType == '.tar.lzma' || compressionType == '.tlz') {
        debugPrint('lzma format detected but not supported in this version');
        throw Exception('LZMA (.tar.lzma) format not supported');
      } else if (compressionType == '.7z') {
        // Use flutter_7zip for 7z extraction
        try {
          SZArchive.extract(archivePath, destFolder);
          if (deleteArchive) {
            await archiveFile.delete();
          }
          return;
        } catch (e) {
          debugPrint('Error extracting 7z with flutter_7zip: $e');
          throw Exception('Failed to extract 7z file: $e');
        }
      } else if (compressionType == '.rar') {
        // RAR decoding not supported in archive package
        debugPrint('RAR format detected but not supported');
        throw Exception('RAR format not supported');
      } else if (compressionType == '.bz2') {
        final outFile = File(
          p.join(destFolder, p.basenameWithoutExtension(archivePath)),
        );
        await File(archivePath).copy(outFile.path);
        if (deleteArchive) {
          await archiveFile.delete();
        }
        return;
      } else if (compressionType == '.xz') {
        final outFile = File(
          p.join(destFolder, p.basenameWithoutExtension(archivePath)),
        );
        final decoded = XZDecoder().decodeBytes(bytes);
        await outFile.writeAsBytes(decoded);
        if (deleteArchive) {
          await archiveFile.delete();
        }
        return;
      } else if (compressionType == '.lzma') {
        debugPrint('lzma format detected but not supported in this version');
        throw Exception('LZMA format not supported');
      } else if (compressionType == '.zst') {
        debugPrint('zst format detected but not supported in this version');
        throw Exception('Zstandard format not supported');
      } else if (compressionType == '.dz') {
        // Dzip format - treat as gzip
        final outFile = File(
          p.join(destFolder, p.basenameWithoutExtension(archivePath)),
        );
        final decoded = GZipDecoder().decodeBytes(bytes);
        await outFile.writeAsBytes(decoded);
        if (deleteArchive) {
          await archiveFile.delete();
        }
        return;
      } else {
        throw Exception('Unsupported compression type: $compressionType');
      }

      if (archive != null) {
        for (final file in archive) {
          final filename = file.name;
          if (file.isFile) {
            final data = file.content as List<int>;
            final outputPath = p.join(destFolder, filename);
            final outputFile = File(outputPath);
            await outputFile.create(recursive: true);
            await outputFile.writeAsBytes(data);
          } else {
            final dirPath = p.join(destFolder, filename);
            await Directory(dirPath).create(recursive: true);
          }
        }
      }

      if (deleteArchive) {
        await archiveFile.delete();
      }
    } catch (e) {
      debugPrint('Error decompressing $archivePath: $e');
      rethrow;
    }
  }

  /// Lists all decompressed dictionary files in a source folder
  Future<Set<String>> listDecompressedFiles({String? sourceName}) async {
    final result = <String>{};

    if (sourceName != null && sourceName.isNotEmpty) {
      final dir = await getStorageDirectory(sourceName: sourceName);
      await _addDictFilesFromDir(dir, result);
    }

    final rootDir = await getStorageDirectory();
    await _addDictFilesFromDir(rootDir, result);

    return result;
  }

  Future<void> _addDictFilesFromDir(Directory dir, Set<String> result) async {
    if (!await dir.exists()) return;
    try {
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File) {
          final name = p.basename(entity.path);
          final base = getBaseNameFromDictFile(name);
          if (base != null) {
            result.add(name);
          }
        }
      }
    } catch (e) {
      debugPrint('Error listing directory ${dir.path}: $e');
    }
  }

  /// Migration status tracking
  static const String _migrationStatusFile = 'migration_status.json';

  /// Reads migration status from file
  Future<MigrationStatus> _readMigrationStatus() async {
    try {
      final storageDir = await getStorageDirectory();
      final statusFile = File(p.join(storageDir.path, _migrationStatusFile));
      if (!await statusFile.exists()) {
        return MigrationStatus();
      }
      final content = await statusFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return MigrationStatus.fromJson(json);
    } catch (e) {
      debugPrint('Error reading migration status: $e');
      return MigrationStatus();
    }
  }

  /// Saves migration status to file
  Future<void> _saveMigrationStatus(MigrationStatus status) async {
    try {
      final storageDir = await getStorageDirectory();
      final statusFile = File(p.join(storageDir.path, _migrationStatusFile));
      await statusFile.writeAsString(jsonEncode(status.toJson()));
    } catch (e) {
      debugPrint('Error saving migration status: $e');
    }
  }

  /// Migration: Decompresses all archive files in storage
  /// Continues gracefully even if some files fail, tracks progress for resume
  Future<MigrationResult> migrateToDecompressed() async {
    final storageDir = await getStorageDirectory();

    // Load previous migration status
    final status = await _readMigrationStatus();

    // Find all archive files recursively
    int migrated = 0;
    int failed = 0;

    await for (final entity in storageDir.list(recursive: true)) {
      if (entity is File) {
        final filename = p.basename(entity.path);

        // Skip already processed files
        if (status.processedFiles.contains(filename)) {
          debugPrint('Skipping already processed: $filename');
          continue;
        }

        // Skip files marked as failed (unless we want to retry)
        if (status.failedFiles.contains(filename)) {
          debugPrint('Skipping previously failed (will retry): $filename');
        }

        final compressionType = detectCompressionType(filename);

        if (compressionType != null) {
          try {
            final baseName = extractBaseName(filename);
            if (baseName == null) {
              debugPrint('Could not extract base name from: $filename');
              status.failedFiles.add(filename);
              failed++;
              continue;
            }

            // Get the parent directory (source folder)
            final parentDir = Directory(p.dirname(entity.path));

            // Decompress in place
            await decompressAndCleanup(
              entity.path,
              parentDir.path,
              deleteArchive: true,
            );

            // Compute MD5 and update metadata (using timestamp from filename)
            final timestamp = extractTimestamp(filename);
            await updateChecksumMetadata(
              baseName,
              '',
              timestamp ?? DateTime.now(),
            );

            // Mark as processed
            status.processedFiles.add(filename);
            migrated++;
            debugPrint('Migrated: $filename -> $baseName');

            // Save progress periodically (every 5 files)
            if (migrated % 5 == 0) {
              status.lastRun = DateTime.now();
              await _saveMigrationStatus(status);
            }
          } catch (e) {
            debugPrint('Failed to migrate $filename: $e');
            status.failedFiles.add(filename);
            failed++;
            // Continue with other files - don't break on failure
          }
        }
      }
    }

    // Save final status
    status.lastRun = DateTime.now();
    await _saveMigrationStatus(status);

    return MigrationResult(
      migrated: migrated,
      failed: failed,
      totalProcessed: status.processedFiles.length,
    );
  }
}

/// Represents migration status for tracking progress
class MigrationStatus {
  final Set<String> processedFiles;
  final Set<String> failedFiles;
  DateTime? lastRun;

  MigrationStatus({
    Set<String>? processedFiles,
    Set<String>? failedFiles,
    this.lastRun,
  }) : processedFiles = processedFiles ?? {},
       failedFiles = failedFiles ?? {};

  Map<String, dynamic> toJson() => {
    'processedFiles': processedFiles.toList(),
    'failedFiles': failedFiles.toList(),
    'lastRun': lastRun?.toIso8601String(),
  };

  factory MigrationStatus.fromJson(Map<String, dynamic> json) {
    return MigrationStatus(
      processedFiles:
          (json['processedFiles'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet() ??
          {},
      failedFiles:
          (json['failedFiles'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet() ??
          {},
      lastRun: json['lastRun'] != null
          ? DateTime.tryParse(json['lastRun'] as String)
          : null,
    );
  }
}

/// Result of migration operation
class MigrationResult {
  final int migrated;
  final int failed;
  final int totalProcessed;

  MigrationResult({
    required this.migrated,
    required this.failed,
    required this.totalProcessed,
  });

  @override
  String toString() =>
      'MigrationResult(migrated: $migrated, failed: $failed, totalProcessed: $totalProcessed)';
}
