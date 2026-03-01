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
            'Network error: Failed to connect. Please check your internet connection.');
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
        r'\[.*?\]\(((?:https?)://[^\s)]+' + archiveExt + r')\)',
        caseSensitive: false);
    for (final m in absMarkdown.allMatches(content)) {
      final l = m.group(1);
      if (l != null) links.add(l);
    }

    // Relative markdown links
    if (baseUrl.isNotEmpty) {
      final relMarkdown = RegExp(
          r'\[.*?\]\(((?:\.{0,2}/)?[^\s)]+' + archiveExt + r')\)',
          caseSensitive: false);
      for (final m in relMarkdown.allMatches(content)) {
        final rel = m.group(1);
        if (rel != null && !rel.startsWith('http')) {
          links.add(Uri.parse(baseUrl).resolve(rel).toString());
        }
      }
    }

    // Plain absolute URLs
    // Using [^\s"'<>]+ for better boundary control
    final plainAbs = RegExp(r'''(?:https?)://[^\s"'<>]+''' + archiveExt, caseSensitive: false);
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
  Future<DictionaryStatus> getDictionaryStatus(String url, Isar isar, {String? sourceName}) async {
    final fileName = _storageService.sanitizeFileName(p.basename(url));
    final upstreamTimestamp = _storageService.extractTimestamp(fileName);

    final fileExists = await _storageService.dictionaryExists(fileName, sourceName: sourceName);

    if (!fileExists) {
      // Check for timestamped version update
      final existingVersion = await _storageService.findExistingVersion(fileName, sourceName: sourceName);
      if (existingVersion != null) {
        final localTimestamp = _storageService.extractTimestamp(p.basename(existingVersion.path));
        
        // If we have both timestamps, compare them.
        if (upstreamTimestamp != null && localTimestamp != null) {
          if (upstreamTimestamp.isAfter(localTimestamp)) {
            return DictionaryStatus.updateAvailable;
          } else {
            return DictionaryStatus.upToDate;
          }
        }
        
        // Fallback for files without timestamps in filenames
        return DictionaryStatus.updateAvailable;
      }
      
      return DictionaryStatus.newFile;
    }

    // File exists exactly — if it has a timestamp, it's definitely up to date
    // because any change in content would result in a different filename (different timestamp).
    if (upstreamTimestamp != null) {
      return DictionaryStatus.upToDate;
    }

    // Fallback logic for non-timestamped filenames (e.g. static names)
    // File exists — check if we have metadata
    var query = isar.dictionaryMetadatas.filter().nameEqualTo(fileName);
    if (sourceName != null && sourceName.isNotEmpty) {
      query = query.sourceNameEqualTo(sourceName);
    }

    final meta = await query.findFirst();

    if (meta == null) {
      // File is on disk but no metadata — treat as up-to-date to avoid
      // forcing re-download of files the user already has.
      return DictionaryStatus.upToDate;
    }

    // Try to detect remote update via HEAD request and persist lastChecked
    final now = DateTime.now();
    DateTime? remote;
    try {
      remote = await checkRemoteVersion(url);
    } catch (e) {
      debugPrint('Error checking remote version for $url: $e');
    }
    await isar.writeTxn(() async {
      final freshMeta = await query.findFirst();
      if (freshMeta != null) {
        freshMeta.lastChecked = now;
        if (remote != null) freshMeta.remoteLastModified = remote;
        await isar.dictionaryMetadatas.put(freshMeta);
      }
    });
    if (remote != null && remote.isAfter(meta.lastUpdated)) {
      return DictionaryStatus.updateAvailable;
    }
    return DictionaryStatus.upToDate;
  }

  Future<DictionaryMetadata?> getMetadata(String url, Isar isar, {String? sourceName}) async {
    final fileName = _storageService.sanitizeFileName(p.basename(url));
    var query = isar.dictionaryMetadatas.filter().nameEqualTo(fileName);
    if (sourceName != null && sourceName.isNotEmpty) {
      query = query.sourceNameEqualTo(sourceName);
    }
    return query.findFirst();
  }

  // ─── Download ──────────────────────────────────────────────────────────────

  /// Downloads a dictionary and persists metadata to Isar.
  Future<File> downloadDictionary(
    String url,
    Isar isar, {
    String? sourceName,
    void Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await _storageService.getStorageDirectory(sourceName: sourceName);
    final fileName = _storageService.sanitizeFileName(p.basename(url));
    final savePath = p.join(dir.path, fileName);

    // Clean up old version if it exists (checks both subfolder and root via StorageService)
    final oldVersion = await _storageService.findExistingVersion(fileName, sourceName: sourceName);
    if (oldVersion != null) {
      debugPrint('Replacing old version: ${oldVersion.path} with $fileName');
      try {
        if (await oldVersion.exists()) {
          await oldVersion.delete();
        }
      } catch (e) {
        debugPrint('Error deleting old version: $e');
      }
    }

    try {
      await _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1 && onProgress != null) {
            onProgress(received / total);
          }
        },
        options: Options(
          headers: {HttpHeaders.acceptEncodingHeader: '*'},
        ),
      );

      final file = File(savePath);
      final sizeInBytes = await file.length();
      final sizeMb = sizeInBytes / (1024 * 1024);

      // Persist metadata so next launch detects this file as up-to-date.
      final filenameTimestamp = _storageService.extractTimestamp(fileName);
      DateTime? remoteModified;
      if (filenameTimestamp == null) {
        try {
          remoteModified = await checkRemoteVersion(url);
        } catch (_) {}
      }

      final meta = DictionaryMetadata()
        ..name = fileName
        ..sourceName = sourceName
        ..remoteUrl = url
        ..localPath = savePath
        ..lastUpdated = filenameTimestamp ?? remoteModified ?? DateTime.now()
        ..remoteLastModified = remoteModified
        ..isDownloaded = true
        ..sizeMb = sizeMb;

      await isar.writeTxn(() => isar.dictionaryMetadatas.put(meta));

      return file;
    } on DioException catch (e) {
      // Clean up partial file on failure or cancellation
      final partialFile = File(savePath);
      if (await partialFile.exists()) {
        await partialFile.delete();
      }

      if (e.type == DioExceptionType.cancel) {
        rethrow; // preserve stack trace, analyzer suggests rethrow
      }
      if (e.type == DioExceptionType.connectionError ||
          e.error is SocketException) {
        throw Exception(
            'Network error: Failed to connect. Please check your internet connection.');
      }
      throw Exception('Download failed (${e.type}): ${e.message ?? e.error ?? 'Unknown error'}');
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

  // ─── Remote version ────────────────────────────────────────────────────────

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
