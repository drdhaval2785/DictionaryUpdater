import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sdu/services/dictionary_client.dart';
import 'package:sdu/services/storage_service.dart';

// Use Fake instead of Mock to avoid need for build_runner
class FakeDio extends Fake implements Dio {
  @override
  Future<Response> download(
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
    return Response(requestOptions: RequestOptions(path: urlPath), statusCode: 200);
  }

  @override
  Future<Response<T>> head<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      headers: Headers.fromMap({
        'last-modified': ['Wed, 21 Oct 2015 07:28:00 GMT'],
      }),
    ) as Response<T>;
  }
}

class FakeIsar extends Fake implements Isar {
  @override
  Future<T> writeTxn<T>(Future<T> Function() callback, {bool silent = false}) async {
    return await callback();
  }

  @override
  IsarCollection<T> collection<T>() => FakeCollection<T>() as IsarCollection<T>;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #dictionaryMetadatas || invocation.memberName == #dictionaryMetadatas) {
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
    return FakeQueryBuilder<T>() as QueryBuilder<T, T, QFilterCondition>;
  }
}

class FakeQueryBuilder<T> extends Fake {
  @override
  dynamic noSuchMethod(Invocation invocation) => this;
  
  @override
  Future<T?> findFirst() async => null;
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
    SharedPreferences.setMockInitialValues({
      'custom_storage_path': tempDir.path,
    });
    final prefs = await SharedPreferences.getInstance();
    storageService = StorageService(prefs);
    fakeDio = FakeDio();
    fakeIsar = FakeIsar();
    client = DictionaryClient(fakeDio, storageService);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('downloadDictionary deletes old timestamped version before downloading new one', () async {
    const oldName = 'abhidhAnachintAmaNi__2023-12-06.tar.gz';
    const newName = 'abhidhAnachintAmaNi__2024-02-26.tar.gz';
    const url = 'https://example.com/$newName';
    
    final oldFile = File(p.join(tempDir.path, oldName));
    await oldFile.create();

    expect(await oldFile.exists(), isTrue, reason: 'Old file should exist before download');

    // Run download
    await client.downloadDictionary(url, fakeIsar);

    // VERIFY: The old file should have been deleted by DictionaryClient.downloadDictionary
    expect(await oldFile.exists(), isFalse, reason: 'The old timestamped version should be deleted');
    
    final newFile = File(p.join(tempDir.path, newName));
    expect(await newFile.exists(), isTrue, reason: 'New version should be present');
  });
}
