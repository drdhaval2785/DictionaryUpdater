import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import '../models/dictionary_models.dart';
import '../services/storage_service.dart';

enum DictionaryStatus { newFile, updateAvailable, upToDate }

/// Client for handling dictionary downloads and source parsing.
class DictionaryClient {
  final Dio _dio;
  final StorageService _storageService;

  DictionaryClient(this._dio, this._storageService);

  // ─── URL helpers ───────────────────────────────────────────────────────────

  /// Converts a GitHub blob URL → raw.githubusercontent.com URL.
  static String toRawUrl(String url) {
    final re = RegExp(r'^https://github\.com/([^/]+)/([^/]+)/blob/(.+)$');
    final m = re.firstMatch(url);
    if (m != null) {
      return 'https://raw.githubusercontent.com/'
          '${m.group(1)}/${m.group(2)}/${m.group(3)}';
    }
    return url;
  }

  static String _baseUrl(String rawUrl) {
    final uri = Uri.parse(rawUrl);
    final segs = uri.pathSegments.toList();
    if (segs.isNotEmpty) segs.removeLast();
    return '${uri.replace(pathSegments: segs, query: null)}/';
  }

  // ─── Parse ─────────────────────────────────────────────────────────────────

  Future<List<String>> parseSourceList(String url) async {
    try {
      String content;
      String baseUrl = '';

      if (url.startsWith('data:')) {
        final comma = url.indexOf(',');
        content = Uri.decodeComponent(url.substring(comma + 1));
        baseUrl = '';
      } else {
        final rawUrl = toRawUrl(url);
        baseUrl = _baseUrl(rawUrl);
        final response = await _dio.get<String>(rawUrl);
        content = response.data ?? '';
      }

      return _extractLinks(content, baseUrl);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.error is SocketException) {
        throw Exception(
          'Network error: Failed to connect. Please check your internet connection.',
        );
      }
      throw Exception('Failed to load source list: ${e.message}');
    } catch (e) {
      throw Exception('Failed to parse source list: $e');
    }
  }

  static List<String> _extractLinks(String content, String baseUrl) {
    const archiveExt =
        r'\.(?:tar\.gz|tgz|tar\.bz2|tbz2|tar\.xz|txz|tar\.lzma|tlz|tar\.zst|tzst|zip|7z|rar|bz2|xz|lzma|zst|dz|ifo|index|dict|idx|md|txt)(?!\w)';
    final links = <String>{};

    // Absolute markdown links (http)
    final absMarkdown = RegExp(
      r'\[.*?\]\(((?:https?)://[^\s)]+' + archiveExt + r')',
      caseSensitive: false,
    );
    for (final m in absMarkdown.allMatches(content)) {
      final l = m.group(1);
      if (l != null) links.add(l);
    }

    // Relative markdown links
    if (baseUrl.isNotEmpty) {
      final relMarkdown = RegExp(
        r'\[.*?\]\(((?:\.{0,2}/)?[^\s)]+' + archiveExt + r')',
        caseSensitive: false,
      );
      for (final m in relMarkdown.allMatches(content)) {
        final rel = m.group(1);
        if (rel != null && !rel.startsWith('http')) {
          links.add(Uri.parse(baseUrl).resolve(rel).toString());
        }
      }
    }

    // Plain absolute URLs
    // Using [^\s"'<>]+ for better boundary control
    final plainAbs = RegExp(
      r'''(?:https?)://[^\s"'<>]+''' + archiveExt,
      caseSensitive: false,
    );
    for (final m in plainAbs.allMatches(content)) {
      links.add(m.group(0)!);
    }

    // Plain relative paths
    if (baseUrl.isNotEmpty) {
      final archiveRegex = RegExp(archiveExt + r'$', caseSensitive: false);
      for (final line in content.split('\n')) {
        final t = line.trim();
        final tl = t.toLowerCase();
        if (t.isNotEmpty &&
            !tl.startsWith('http') &&
            archiveRegex.hasMatch(tl)) {
          links.add(Uri.parse(baseUrl).resolve(t).toString());
        }
      }
    }

    return links.toList();
  }

  /// For unit testing only.
  static List<String> extractLinksForTest(String content, String baseUrl) =>
      _extractLinks(content, baseUrl);

  // ─── Status check ──────────────────────────────────────────────────────────

  /// Returns the update status for a dictionary file.
  /// Uses checksum metadata for comparison when available.
  Future<DictionaryStatus> getDictionaryStatus(
    String url,
    Isar isar, {
    String? sourceName,
  }) async {
    final fileName = _storageService.sanitizeFileName(p.basename(url));
    final baseName =
        _storageService.extractBaseName(fileName) ??
        _storageService.sanitizeFileName(fileName);

    // Check if decompressed files exist locally
    final fileExists = await _storageService.hasDecompressedFiles(
      baseName,
      sourceName: sourceName,
    );

    // Get upstream timestamp from filename
    final upstreamTimestamp = _storageService.extractTimestamp(fileName);

    // Get stored checksum entry
    final storedChecksum = await _storageService.getChecksumEntry(baseName);

    if (!fileExists) {
      // No decompressed files found - check for old archive files
      final existingVersion = await _storageService.findExistingVersion(
        fileName,
        sourceName: sourceName,
      );

      if (existingVersion != null) {
        // We have an old version - determine if it's an update
        if (upstreamTimestamp != null) {
          // Compare timestamps from filename
          final localTimestamp = _storageService.extractTimestamp(
            _storageService.extractBaseName(p.basename(existingVersion.path)) ??
                '',
          );
          if (localTimestamp != null) {
            return upstreamTimestamp.isAfter(localTimestamp)
                ? DictionaryStatus.updateAvailable
                : DictionaryStatus.upToDate;
          }
        }

        // No timestamps - use stored checksum
        if (storedChecksum != null && storedChecksum.md5.isNotEmpty) {
          return DictionaryStatus.updateAvailable;
        }

        // Fallback - no way to compare, assume update available
        return DictionaryStatus.updateAvailable;
      }

      return DictionaryStatus.newFile;
    }

    // File exists - use checksum/timestamp for comparison
    if (upstreamTimestamp != null) {
      // Compare timestamp from filename
      if (storedChecksum != null && storedChecksum.timestamp != null) {
        return upstreamTimestamp.isAfter(storedChecksum.timestamp!)
            ? DictionaryStatus.updateAvailable
            : DictionaryStatus.upToDate;
      }
      // If we have upstream timestamp but no stored, likely up to date
      // (first download after migration will set it)
      return DictionaryStatus.upToDate;
    }

    // No timestamp in filename - use HEAD request for comparison
    // First check stored checksum (MD5 based)
    if (storedChecksum != null && storedChecksum.md5.isNotEmpty) {
      // We have stored MD5 - need to compare with remote
      // This is expensive, so we check remote version
      try {
        final remote = await checkRemoteVersion(url);
        if (remote != null) {
          // Update stored timestamp with remote last-modified
          await _storageService.updateChecksumMetadata(
            baseName,
            storedChecksum.md5,
            remote,
          );

          // Compare with stored timestamp
          if (storedChecksum.timestamp != null &&
              remote.isAfter(storedChecksum.timestamp!)) {
            return DictionaryStatus.updateAvailable;
          }
        }
      } catch (e) {
        debugPrint('Error checking remote version: $e');
      }
      return DictionaryStatus.upToDate;
    }

    // No checksum, no timestamp - check with metadata
    final meta = await getMetadata(url, isar, sourceName: sourceName);
    if (meta == null) {
      return DictionaryStatus.upToDate;
    }

    // Try HEAD request
    try {
      final remote = await checkRemoteVersion(url);
      if (remote != null && remote.isAfter(meta.lastUpdated)) {
        return DictionaryStatus.updateAvailable;
      }
    } catch (e) {
      debugPrint('Error checking remote version: $e');
    }

    return DictionaryStatus.upToDate;
  }

  Future<DictionaryMetadata?> getMetadata(
    String url,
    Isar isar, {
    String? sourceName,
  }) async {
    final fileName = _storageService.sanitizeFileName(p.basename(url));
    final baseName = _storageService.extractBaseName(fileName) ?? fileName;

    // Try to find by base name in source
    var query = isar.dictionaryMetadatas.filter().nameContains(
      baseName,
      caseSensitive: false,
    );
    if (sourceName != null && sourceName.isNotEmpty) {
      query = query.sourceNameEqualTo(sourceName);
    }
    return query.findFirst();
  }

  // ─── Download ──────────────────────────────────────────────────────────────

  /// Downloads a dictionary, decompresses it, and persists metadata to Isar.
  Future<File> downloadDictionary(
    String url,
    Isar isar, {
    String? sourceName,
    void Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await _storageService.getStorageDirectory(
      sourceName: sourceName,
    );
    final fileName = _storageService.sanitizeFileName(p.basename(url));
    final savePath = p.join(dir.path, fileName);
    final baseName =
        _storageService.extractBaseName(fileName) ?? fileName.split('.').first;

    // Clean up old decompressed files
    final oldVersion = await _storageService.findExistingVersion(
      fileName,
      sourceName: sourceName,
    );
    if (oldVersion != null) {
      debugPrint('Replacing old version: ${oldVersion.path}');
      try {
        if (await oldVersion.exists()) {
          await oldVersion.delete();
        }
      } catch (e) {
        debugPrint('Error deleting old version: $e');
      }
    }

    // Also clean up any old archive files in the folder
    final oldArchiveFile = File(savePath);
    if (await oldArchiveFile.exists()) {
      await oldArchiveFile.delete();
    }

    try {
      // Download compressed file
      await _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
        options: Options(headers: {HttpHeaders.acceptEncodingHeader: '*'}),
      );

      // Compute MD5 checksum and update checksum metadata BEFORE decompression
      // This way even if decompression fails, we still track the file
      final computedMD5 = await _storageService.computeMD5(savePath);

      // Extract timestamp from filename
      DateTime? timestamp = _storageService.extractTimestamp(fileName);

      // If no timestamp in filename, try HEAD request
      if (timestamp == null) {
        try {
          final remote = await checkRemoteVersion(url);
          if (remote != null) {
            timestamp = remote;
          }
        } catch (_) {}
      }

      // Update checksum metadata before decompression (in case it fails)
      await _storageService.updateChecksumMetadata(
        baseName,
        computedMD5,
        timestamp,
      );

      // Decompress the archive
      debugPrint('Decompressing $fileName to ${dir.path}');
      await _storageService.decompressAndCleanup(
        savePath,
        dir.path,
        deleteArchive: true,
      );

      // Get decompressed file size (sum of all files in folder)
      double sizeMb = 0;
      try {
        final files = await dir.list().toList();
        for (final entity in files) {
          if (entity is File) {
            final name = p.basename(entity.path).toLowerCase();
            // Check if it's a dictionary file
            if (_isDictFile(name)) {
              sizeMb += await entity.length();
            }
          }
        }
        sizeMb = sizeMb / (1024 * 1024);
      } catch (e) {
        debugPrint('Error calculating size: $e');
      }

      // Persist metadata so next launch detects this file as up-to-date.
      final meta = DictionaryMetadata()
        ..name = baseName
        ..sourceName = sourceName
        ..remoteUrl = url
        ..localPath = dir
            .path // Store folder path instead of file
        ..lastUpdated = timestamp ?? DateTime.now()
        ..remoteLastModified = timestamp
        ..isDownloaded = true
        ..sizeMb = sizeMb;

      await isar.writeTxn(() => isar.dictionaryMetadatas.put(meta));

      // Return any file in the directory as representative
      final files = await dir.list().toList();
      final firstFile = files.whereType<File>().firstOrNull ?? File(savePath);
      return firstFile;
    } on DioException catch (e) {
      // Clean up partial file on failure or cancellation
      final partialFile = File(savePath);
      if (await partialFile.exists()) {
        await partialFile.delete();
      }

      if (e.type == DioExceptionType.cancel) {
        rethrow;
      }
      if (e.type == DioExceptionType.connectionError ||
          e.error is SocketException) {
        throw Exception(
          'Network error: Failed to connect. Please check your internet connection.',
        );
      }
      throw Exception(
        'Download failed (${e.type}): ${e.message ?? e.error ?? 'Unknown error'}',
      );
    } catch (e) {
      // Clean up partial file on other errors too
      final partialFile = File(savePath);
      if (await partialFile.exists()) {
        await partialFile.delete();
      }
      debugPrint('DictionaryClient error during download: $e');
      throw Exception('Download failed: $e');
    }
  }

  bool _isDictFile(String filename) {
    const dictExtensions = [
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
    for (final ext in dictExtensions) {
      if (filename.toLowerCase().endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  // ─── Remote version ───────────────────────────────────────────────────────

  Future<DateTime?> checkRemoteVersion(String url) async {
    try {
      final response = await _dio.head<dynamic>(url);
      final lm = response.headers.value(HttpHeaders.lastModifiedHeader);
      if (lm != null) return HttpDate.parse(lm);
    } catch (e) {
      debugPrint('Error checking remote version for $url: $e');
      rethrow;
    }
    return null;
  }
}
