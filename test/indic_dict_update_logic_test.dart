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
    test('extractBaseName correctly identifies the stable part of the filename', () {
      expect(storageService.extractBaseName('abhidhAnachintAmaNi__2023-12-06.tar.gz'), 
             equals('abhidhAnachintAmaNi'));
      expect(storageService.extractBaseName('sa-IAST-kRdanta__v2.zip'), 
             equals('sa-IAST-kRdanta'));
      expect(storageService.extractBaseName('normal_file.tar.gz'), 
             isNull); // Not an indic-dict pattern (needs __)
    });

    test('extractTimestamp correctly parses the timestamp from filename', () {
      final ts = storageService.extractTimestamp('anekArthadhvanimanjarI__2022-01-22_15-15-47Z__0MB.tar.gz');
      expect(ts, isNotNull);
      expect(ts!.isUtc, isTrue);
      expect(ts.year, 2022);
      expect(ts.month, 1);
      expect(ts.day, 22);
      expect(ts.hour, 15);
      expect(ts.minute, 15);
      expect(ts.second, 47);
    });

    test('findExistingVersion detects older version with different timestamp', () async {
      const oldName = 'abhidhAnachintAmaNi__2023-12-06_13-57-22Z__0MB.tar.gz';
      const newName = 'abhidhAnachintAmaNi__2024-02-26_10-00-00Z__1MB.tar.gz';

      final storageDir = p.join(tempDir.path, 'DictionaryData');
      
      // 1. Create the "old" file on disk
      final oldFile = File(p.join(storageDir, oldName));
      await oldFile.create(recursive: true);
      
      // 2. Search for existing version of the "new" file
      final found = await storageService.findExistingVersion(newName);
      
      expect(found, isNotNull, reason: 'Should find the old version even with different timestamp');
      expect(p.basename(found!.path), equals(oldName));
    });

    test('findExistingVersion returns null if exact file already exists', () async {
      const fileName = 'exact_match__2023.tar.gz';
      final storageDir = p.join(tempDir.path, 'DictionaryData');
      final file = File(p.join(storageDir, fileName));
      await file.create(recursive: true);

      final found = await storageService.findExistingVersion(fileName);
      expect(found, isNull, reason: 'Should return null if the exact file is already there (no replacement needed)');
    });

    test('dictionaryExists finds files in root when sourceName is provided', () async {
      const fileName = 'root_file__2023.zip';
      final rootDir = p.join(tempDir.path, 'DictionaryData');
      await File(p.join(rootDir, fileName)).create(recursive: true);

      final exists = await storageService.dictionaryExists(fileName, sourceName: 'SomeSource');
      expect(exists, isTrue, reason: 'Should find the file in root even if sourceName is SomeSource');
    });

    test('findExistingVersion finds old version in root when searching from source subfolder', () async {
      const oldName = 'base_name__old.zip';
      const newName = 'base_name__new.zip';
      final rootDir = p.join(tempDir.path, 'DictionaryData');
      await File(p.join(rootDir, oldName)).create(recursive: true);

      final found = await storageService.findExistingVersion(newName, sourceName: 'SomeSource');
      expect(found, isNotNull);
      expect(p.basename(found!.path), equals(oldName));
    });
  });
}
