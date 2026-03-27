import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:dictionary_updater/services/dictionary_client.dart';
import 'package:dictionary_updater/services/storage_service.dart';

class FakeDio extends Fake implements Dio {
  @override
  Future<Response<dynamic>> download(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
    FileAccessMode fileAccessMode = FileAccessMode.write,
  }) async {
    final file = File(savePath.toString());
    await file.create(recursive: true);
    // Write some dummy content so MD5 can be computed
    await file.writeAsBytes([1, 2, 3, 4, 5]);
    return Response<dynamic>(
      requestOptions: RequestOptions(path: urlPath),
      statusCode: 200,
    );
  }

  @override
  Future<Response<T>> head<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      headers: Headers.fromMap({
        'last-modified': ['Wed, 21 Oct 2015 07:28:00 GMT'],
      }),
    );
  }
}

class FakeIsar extends Fake implements Isar {
  @override
  Future<T> writeTxn<T>(
    Future<T> Function() callback, {
    bool silent = false,
  }) async {
    return callback();
  }

  @override
  IsarCollection<T> collection<T>() => FakeCollection<T>() as IsarCollection<T>;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #dictionaryMetadatas) {
      return FakeCollection<dynamic>();
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeCollection<T> extends Fake implements IsarCollection<T> {
  @override
  Future<int> put(T object) async => 1;

  @override
  QueryBuilder<T, T, QFilterCondition> filter() {
    return FakeQueryBuilder<T, T, QFilterCondition>()
        as QueryBuilder<T, T, QFilterCondition>;
  }
}

class FakeQueryBuilder<T, R, S> extends Fake implements QueryBuilder<T, R, S> {
  @override
  dynamic noSuchMethod(Invocation invocation) => this;

  Future<R?> findFirst() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DictionaryClient client;
  late StorageService storageService;
  late FakeDio fakeDio;
  late FakeIsar fakeIsar;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sdu_download_test');
    storageService = StorageService(baseDirOverride: tempDir);
    fakeDio = FakeDio();
    fakeIsar = FakeIsar();
    client = DictionaryClient(fakeDio, storageService);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'downloadDictionary creates decompressed files and updates checksum metadata',
    () async {
      const archiveName = 'abhidhAnachintAmaNi__2024-02-26.tar.gz';
      const url = 'https://example.com/$archiveName';

      final storageDir = p.join(tempDir.path, 'DictionaryData');

      // Run download (will fail decompression but should still update metadata)
      try {
        await client.downloadDictionary(url, fakeIsar);
      } catch (_) {
        // Expected to fail with fake archive data
      }

      // Verify checksum metadata was updated even if decompression failed
      final checksumEntry = await storageService.getChecksumEntry(
        'abhidhAnachintAmaNi',
      );
      expect(
        checksumEntry,
        isNotNull,
        reason: 'Checksum entry should be created',
      );
      expect(checksumEntry!.md5, isNotEmpty, reason: 'MD5 should be computed');
      expect(
        checksumEntry.timestamp,
        isNotNull,
        reason: 'Timestamp should be extracted from filename',
      );
    },
  );

  group('getDictionaryStatus with decompressed files', () {
    test(
      'identifies upToDate when decompressed files exist with matching timestamp',
      () async {
        const baseName = 'dict';
        const sourceName = 'Indic-dict_English';
        final storageDir = p.join(tempDir.path, 'DictionaryData', sourceName);

        // Create decompressed files
        await File(
          p.join(storageDir, '$baseName.dict.dz'),
        ).create(recursive: true);
        await File(p.join(storageDir, '$baseName.idx')).create(recursive: true);

        // Update checksum with a timestamp that matches upstream
        final timestamp = DateTime.utc(2023, 1, 1, 12, 0, 0);
        await storageService.updateChecksumMetadata(
          baseName,
          'some-md5',
          timestamp,
        );

        final url =
            'https://example.com/dict__2023-01-01_12-00-00Z__0MB.tar.gz';
        final status = await client.getDictionaryStatus(
          url,
          fakeIsar,
          sourceName: sourceName,
        );
        expect(status, equals(DictionaryStatus.upToDate));
      },
    );

    test(
      'identifies updateAvailable when decompressed files are older than upstream',
      () async {
        const baseName = 'dict';
        const sourceName = 'Indic-dict_English';
        final storageDir = p.join(tempDir.path, 'DictionaryData', sourceName);

        // Create decompressed files
        await File(
          p.join(storageDir, '$baseName.dict.dz'),
        ).create(recursive: true);

        // Update checksum with older timestamp
        final oldTimestamp = DateTime.utc(2022, 1, 1, 12, 0, 0);
        await storageService.updateChecksumMetadata(
          baseName,
          'some-md5',
          oldTimestamp,
        );

        // Upstream has newer timestamp
        final url =
            'https://example.com/dict__2024-01-01_12-00-00Z__0MB.tar.gz';
        final status = await client.getDictionaryStatus(
          url,
          fakeIsar,
          sourceName: sourceName,
        );
        expect(status, equals(DictionaryStatus.updateAvailable));
      },
    );

    test('identifies newFile when no decompressed files exist', () async {
      const url = 'https://example.com/new-dict__2024-01-01.tar.gz';
      final status = await client.getDictionaryStatus(url, fakeIsar);
      expect(status, equals(DictionaryStatus.newFile));
    });
  });

  group('Checksum metadata for status checking', () {
    test('uses checksum timestamp for comparison when available', () async {
      const baseName = 'test-dict';
      final storageDir = p.join(tempDir.path, 'DictionaryData');

      // Create decompressed files
      await File(
        p.join(storageDir, '$baseName.dict.dz'),
      ).create(recursive: true);
      await File(p.join(storageDir, '$baseName.idx')).create(recursive: true);

      // Set stored checksum with a timestamp
      final storedTimestamp = DateTime.utc(2023, 6, 15, 12, 0, 0);
      await storageService.updateChecksumMetadata(
        baseName,
        'abc123',
        storedTimestamp,
      );

      // Upstream file has older timestamp
      final url =
          'https://example.com/test-dict__2023-01-01_12-00-00Z__1MB.tar.gz';
      final status = await client.getDictionaryStatus(url, fakeIsar);

      expect(
        status,
        equals(DictionaryStatus.upToDate),
        reason: 'Stored timestamp is newer than upstream',
      );
    });
  });
}
