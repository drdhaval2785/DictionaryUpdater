import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sdu/services/storage_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  late StorageService storageService;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sdu_test_indic');
    SharedPreferences.setMockInitialValues({
      'custom_storage_path': tempDir.path,
    });
    final prefs = await SharedPreferences.getInstance();
    storageService = StorageService(prefs);
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

    test('findExistingVersion detects older version with different timestamp', () async {
      const oldName = 'abhidhAnachintAmaNi__2023-12-06_13-57-22Z__0MB.tar.gz';
      const newName = 'abhidhAnachintAmaNi__2024-02-26_10-00-00Z__1MB.tar.gz';

      // 1. Create the "old" file on disk
      final oldFile = File(p.join(tempDir.path, oldName));
      await oldFile.create();
      
      // 2. Search for existing version of the "new" file
      final found = await storageService.findExistingVersion(newName);
      
      expect(found, isNotNull, reason: 'Should find the old version even with different timestamp');
      expect(p.basename(found!.path), equals(oldName));
    });

    test('findExistingVersion returns null if exact file already exists', () async {
      const fileName = 'exact_match__2023.tar.gz';
      final file = File(p.join(tempDir.path, fileName));
      await file.create();

      final found = await storageService.findExistingVersion(fileName);
      expect(found, isNull, reason: 'Should return null if the exact file is already there (no replacement needed)');
    });

    test('findExistingVersion returns null if no version exists', () async {
      final found = await storageService.findExistingVersion('non_existent__2023.zip');
      expect(found, isNull);
    });
  });
}
