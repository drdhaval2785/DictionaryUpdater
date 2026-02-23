import 'dart:io';
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

      if (url.startsWith('file://')) {
        final filePath = Uri.parse(url).toFilePath();
        content = await File(filePath).readAsString();
        final fileUri = Uri.file(filePath);
        final segs =
            fileUri.pathSegments.sublist(0, fileUri.pathSegments.length - 1);
        baseUrl = '${fileUri.replace(pathSegments: segs)}/';
      } else if (url.startsWith('data:')) {
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
        r'\.(?:tar\.gz|tgz|tar\.bz2|tbz2|tar\.xz|txz|tar\.lzma|tlz|tar\.zst|tzst|zip|7z|rar|bz2|xz|lzma|zst|dz)';
    final links = <String>{};

    // Absolute markdown links
    final absMarkdown = RegExp(
        r'\[.*?\]\((https?://[^\s)]+?' + archiveExt + r')\)',
        caseSensitive: false);
    for (final m in absMarkdown.allMatches(content)) {
      final l = m.group(1);
      if (l != null) links.add(l);
    }

    // Relative markdown links
    if (baseUrl.isNotEmpty) {
      final relMarkdown = RegExp(
          r'\[.*?\]\(((?:\.{0,2}/)?[^\s)]+?' + archiveExt + r')\)',
          caseSensitive: false);
      for (final m in relMarkdown.allMatches(content)) {
        final rel = m.group(1);
        if (rel != null && !rel.startsWith('http')) {
          links.add(Uri.parse(baseUrl).resolve(rel).toString());
        }
      }
    }

    // Plain absolute URLs
    final plainAbs = RegExp(r'https?://\S+?' + archiveExt, caseSensitive: false);
    for (final m in plainAbs.allMatches(content)) {
      links.add(m.group(0)!);
    }

    // Plain relative paths
    if (baseUrl.isNotEmpty) {
      final archiveRegex = RegExp(archiveExt + r'$', caseSensitive: false);
      for (final line in content.split('\n')) {
        final t = line.trim().toLowerCase();
        if (t.isNotEmpty &&
            !t.startsWith('http') &&
            archiveRegex.hasMatch(t)) {
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
  /// Priority:
  ///  1. If file does NOT exist on disk → newFile
  ///  2. If file exists but no Isar record → upToDate (treat pre-existing files as current)
  ///  3. If remote Last-Modified > local lastUpdated → updateAvailable
  ///  4. Otherwise → upToDate
  Future<DictionaryStatus> getDictionaryStatus(String url, Isar isar, {String? sourceName}) async {
    final fileName = _storageService.sanitizeFileName(p.basename(url));
    final fileExists = await _storageService.dictionaryExists(fileName, sourceName: sourceName);

    if (!fileExists) return DictionaryStatus.newFile;

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

    // Try to detect remote update via HEAD request
    final remote = await checkRemoteVersion(url);
    if (remote != null && remote.isAfter(meta.lastUpdated)) {
      return DictionaryStatus.updateAvailable;
    }
    return DictionaryStatus.upToDate;
  }

  // ─── Download ──────────────────────────────────────────────────────────────

  /// Downloads a dictionary and persists metadata to Isar so it is recognized
  /// as "up to date" on next launch.
  Future<File> downloadDictionary(
    String url,
    Isar isar, {
    String? sourceName,
    void Function(double)? onProgress,
  }) async {
    final dir = await _storageService.getStorageDirectory(sourceName: sourceName);
    final fileName = _storageService.sanitizeFileName(p.basename(url));
    final savePath = p.join(dir.path, fileName);

    try {
      await _dio.download(
        url,
        savePath,
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

      // Persist metadata so next launch detects this file as up-to-date.
      DateTime? remoteModified;
      try {
        remoteModified = await checkRemoteVersion(url);
      } catch (_) {}

      final meta = DictionaryMetadata()
        ..name = fileName
        ..sourceName = sourceName
        ..remoteUrl = url
        ..localPath = savePath
        ..lastUpdated = remoteModified ?? DateTime.now()
        ..remoteLastModified = remoteModified
        ..isDownloaded = true;

      await isar.writeTxn(() => isar.dictionaryMetadatas.put(meta));

      return file;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.error is SocketException) {
        throw Exception(
            'Network error: Failed to connect. Please check your internet connection.');
      }
      throw Exception('Download failed: ${e.message}');
    } catch (e) {
      throw Exception('Download failed: $e');
    }
  }

  // ─── Remote version ────────────────────────────────────────────────────────

  Future<DateTime?> checkRemoteVersion(String url) async {
    if (url.startsWith('file://')) {
      final file = File(Uri.parse(url).toFilePath());
      return (await file.exists()) ? file.lastModified() : null;
    }
    try {
      final response = await _dio.head<dynamic>(url);
      final lm = response.headers.value(HttpHeaders.lastModifiedHeader);
      if (lm != null) return HttpDate.parse(lm);
    } catch (_) {}
    return null;
  }
}
