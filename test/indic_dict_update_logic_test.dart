import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dictionary_updater/services/storage_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storageService;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sdu_test_indic');
    storageService = StorageService(baseDirOverride: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Indic-dict Update Logic (StorageService)', () {
    test(
      'extractBaseName correctly identifies the stable part of the filename',
      () {
        expect(
          storageService.extractBaseName(
            'abhidhAnachintAmaNi__2023-12-06.tar.gz',
          ),
          equals('abhidhAnachintAmaNi'),
        );
        expect(
          storageService.extractBaseName('sa-IAST-kRdanta__v2.zip'),
          equals('sa-IAST-kRdanta'),
        );
        expect(
          storageService.extractBaseName(
            'abhidhAnachintAmaNi__2024-02-26_10-00-00Z__1MB.tar.gz',
          ),
          equals('abhidhAnachintAmaNi'),
        );
        expect(
          storageService.extractBaseName('normal_file.tar.gz'),
          isNull,
        ); // Not an indic-dict pattern (needs __)
      },
    );

    test('extractTimestamp correctly parses the timestamp from filename', () {
      final ts = storageService.extractTimestamp(
        'anekArthadhvanimanjarI__2022-01-22_15-15-47Z__0MB.tar.gz',
      );
      expect(ts, isNotNull);
      expect(ts!.isUtc, isTrue);
      expect(ts.year, 2022);
      expect(ts.month, 1);
      expect(ts.day, 22);
      expect(ts.hour, 15);
      expect(ts.minute, 15);
      expect(ts.second, 47);
    });

    test(
      'getBaseNameFromDictFile extracts base name from decompressed dictionary files',
      () {
        expect(
          storageService.getBaseNameFromDictFile('sa-IAST-kRdanta.dict.dz'),
          equals('sa-IAST-kRdanta'),
        );
        expect(
          storageService.getBaseNameFromDictFile('abhidhAnachintAmaNi.idx'),
          equals('abhidhAnachintAmaNi'),
        );
        expect(
          storageService.getBaseNameFromDictFile('dict.wav'),
          equals('dict'),
        );
        expect(
          storageService.getBaseNameFromDictFile('random.txt'),
          isNull,
        ); // Not a dictionary file
      },
    );

    test(
      'hasDecompressedFiles finds decompressed files in source folder',
      () async {
        const sourceName = 'Indic-dict_English-Sanskrit';
        final sourceDir = p.join(tempDir.path, 'DictionaryData', sourceName);

        // Create decompressed dictionary files
        await File(
          p.join(sourceDir, 'sa-IAST-kRdanta.dict.dz'),
        ).create(recursive: true);
        await File(
          p.join(sourceDir, 'sa-IAST-kRdanta.idx'),
        ).create(recursive: true);

        final exists = await storageService.hasDecompressedFiles(
          'sa-IAST-kRdanta',
          sourceName: sourceName,
        );
        expect(exists, isTrue, reason: 'Should find decompressed files');
      },
    );

    test(
      'hasDecompressedFiles finds decompressed files in root folder',
      () async {
        final rootDir = p.join(tempDir.path, 'DictionaryData');

        // Create decompressed dictionary files in root
        await File(
          p.join(rootDir, 'some-dict.dict.dz'),
        ).create(recursive: true);
        await File(p.join(rootDir, 'some-dict.idx')).create(recursive: true);

        final exists = await storageService.hasDecompressedFiles('some-dict');
        expect(
          exists,
          isTrue,
          reason: 'Should find decompressed files in root',
        );
      },
    );

    test(
      'hasDecompressedFiles returns false when no decompressed files exist',
      () async {
        final rootDir = p.join(tempDir.path, 'DictionaryData');
        await Directory(rootDir).create(recursive: true);

        final exists = await storageService.hasDecompressedFiles('nonexistent');
        expect(exists, isFalse);
      },
    );

    test('detectCompressionType correctly identifies archive types', () {
      expect(
        storageService.detectCompressionType('file.tar.gz'),
        equals('.tar.gz'),
      );
      expect(storageService.detectCompressionType('file.tgz'), equals('.tgz'));
      expect(storageService.detectCompressionType('file.zip'), equals('.zip'));
      expect(
        storageService.detectCompressionType('file.tar.bz2'),
        equals('.tar.bz2'),
      );
      expect(storageService.detectCompressionType('file.7z'), equals('.7z'));
      expect(storageService.detectCompressionType('file.txt'), isNull);
    });

    test('findExistingVersion finds old decompressed version', () async {
      const sourceName = 'Indic-dict_English-Sanskrit';
      final sourceDir = p.join(tempDir.path, 'DictionaryData', sourceName);

      // Create old decompressed file
      await File(
        p.join(sourceDir, 'abhidhAnachintAmaNi.dict.dz'),
      ).create(recursive: true);

      // Search for new archive name
      final found = await storageService.findExistingVersion(
        'abhidhAnachintAmaNi__2024-02-26_10-00-00Z__1MB.tar.gz',
        sourceName: sourceName,
      );

      expect(
        found,
        isNotNull,
        reason: 'Should find the old decompressed version',
      );
    });
  });

  group('Checksum Metadata', () {
    test(
      'updateChecksumMetadata and readChecksumMetadata work correctly',
      () async {
        const baseName = 'test-dict';
        const md5 = 'abc123';
        final timestamp = DateTime(2024, 1, 1);

        await storageService.updateChecksumMetadata(baseName, md5, timestamp);

        final metadata = await storageService.readChecksumMetadata();
        expect(metadata.containsKey(baseName), isTrue);
        expect(metadata[baseName]!.md5, equals(md5));
        expect(metadata[baseName]!.timestamp, equals(timestamp));
      },
    );

    test('getChecksumEntry returns correct entry', () async {
      const baseName = 'test-dict';
      await storageService.updateChecksumMetadata(
        baseName,
        'md5hash',
        DateTime(2024, 1, 1),
      );

      final entry = await storageService.getChecksumEntry(baseName);
      expect(entry, isNotNull);
      expect(entry!.baseName, equals(baseName));
    });

    test('getChecksumEntry returns null for non-existent entry', () async {
      final entry = await storageService.getChecksumEntry('nonexistent');
      expect(entry, isNull);
    });
  });
}
